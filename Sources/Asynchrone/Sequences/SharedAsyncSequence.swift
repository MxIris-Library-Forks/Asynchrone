import Foundation

/// An async sequence that can be shared between multiple tasks.
///
/// The base sequence is iterated once, starting when the first iterator is made, and
/// every iterator receives the elements it emits from the moment that iterator was made;
/// earlier elements are not replayed. Once the base sequence has finished, iterators made
/// afterwards finish at once, rethrowing its error if it failed.
///
/// ```swift
/// let sequence = PassthroughAsyncSequence<String>().shared()
///
/// let firstConsumer = Task {
///     try await sequence.collect()
/// }
///
/// let secondConsumer = Task.detached {
///     try await sequence.collect()
/// }
///
/// // Each consumer receives only the elements yielded after it
/// // started iterating, so give both a moment to start.
/// try await Task.sleep(seconds: 0.1)
/// sequence.yield("a")
/// sequence.yield("ab")
/// sequence.finish(with: "abc")
///
/// print(try await firstConsumer.value)
/// print(try await secondConsumer.value)
///
/// // Prints:
/// // ["a", "ab", "abc"]
/// // ["a", "ab", "abc"]
/// ```
public struct SharedAsyncSequence<Base: AsyncSequence>: AsyncSequence, Sendable
where
Base: Sendable,
Base.Element: Sendable {
    /// The type of async iterator.
    public typealias AsyncIterator = AsyncThrowingStream<Base.Element, Error>.Iterator
    
    /// The type of elements streamed.
    public typealias Element = Base.Element
    
    // Private
    private var base: Base
    private let manager: SubSequenceManager<Base>

    // MARK: SharedAsyncSequence (Public Properties)

    /// Creates a shareable async sequence that can be used across multiple tasks.
    /// - Parameters:
    ///   - base: The async sequence in which this sequence receives it's elements.
    public init(_ base: Base) {
        self.base = base
        self.manager = SubSequenceManager<Base>(base)
    }
    
    // MARK: AsyncSequence
    
    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> AsyncThrowingStream<Base.Element, Error>.Iterator {
        self.manager.makeAsyncIterator()
    }
}

// MARK: CurrentElementAsyncSequence extension

extension SharedAsyncSequence {
    /// Yield a new element to the sequence.
    ///
    /// Yielding a new element will update this async sequence's `element` property
    /// along with emitting it through the sequence.
    /// - Parameter element: The element to yield.
    public func yield<Element>(_ element: Element) async
    where Base == CurrentElementAsyncSequence<Element>, Element: Sendable  {
        await self.base.yield(element)
    }
    
    /// Mark the sequence as finished by having it's iterator emit nil.
    ///
    /// Once finished, any calls to yield will result in no change.
    public func finish<Element>() async where Base == CurrentElementAsyncSequence<Element> {
        await self.base.finish()
    }
    
    /// Emit one last element beford marking the sequence as finished by having it's iterator emit nil.
    ///
    /// Once finished, any calls to yield will result in no change.
    /// - Parameter element: The element to emit.
    public func finish<Element>(with element: Element) async
    where Base == CurrentElementAsyncSequence<Element>, Element: Sendable {
        await self.base.finish(with: element)
    }
    
    /// The element wrapped by this async sequence, emitted as a new element whenever it changes.
    public func element<Element>() async -> Element
    where Base == CurrentElementAsyncSequence<Element>, Element: Sendable {
        await self.base.element
    }
}

// MARK: PassthroughAsyncSequence extension

extension SharedAsyncSequence {
    /// Yield a new element to the sequence.
    ///
    /// Yielding a new element will emit it through the sequence.
    /// - Parameter element: The element to yield.
    public func yield<Element>(_ element: Element) where Base == PassthroughAsyncSequence<Element>  {
        self.base.yield(element)
    }
    
    /// Mark the sequence as finished by having it's iterator emit nil.
    ///
    /// Once finished, any calls to yield will result in no change.
    public func finish<Element>() where Base == PassthroughAsyncSequence<Element> {
        self.base.finish()
    }
    
    /// Emit one last element beford marking the sequence as finished by having it's iterator emit nil.
    ///
    /// Once finished, any calls to yield will result in no change.
    /// - Parameter element: The element to emit.
    public func finish<Element>(with element: Element) where Base == PassthroughAsyncSequence<Element> {
        self.base.finish(with: element)
    }
}

// MARK: Sub sequence manager

/// Broadcasts the elements of the base sequence to every subscriber.
///
/// Subscribers are registered synchronously, inside `makeAsyncIterator()`, behind a lock.
/// Registering them from a background task instead raced with the subscriber going away:
/// a subscriber dropped before its registration ran was registered for good, and its
/// termination handler kept the manager, and so the subscription to the base, alive forever.
fileprivate final class SubSequenceManager<Base: AsyncSequence>: @unchecked Sendable where Base: Sendable, Base.Element: Sendable {
    fileprivate typealias Element = Base.Element
    private typealias Continuation = AsyncThrowingStream<Element, Error>.Continuation

    // Private
    private let base: Base
    private let lock = NSLock()
    private var continuations: [Int: Continuation] = [:]
    private var lastSubscriberIdentifier = 0
    private var subscriptionTask: Task<Void, Never>?
    /// How the base sequence ended, once it has.
    private var completion: Result<Void, Error>?

    // MARK: Initialization

    fileprivate init(_ base: Base) {
        self.base = base
    }

    deinit {
        self.subscriptionTask?.cancel()
    }

    // MARK: API

    /// Creates an new stream and returns its async iterator that emits elements of base async sequence.
    ///
    /// The subscriber is registered before this returns. If the base sequence has already
    /// finished, the stream finishes at once instead.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    fileprivate func makeAsyncIterator() -> AsyncThrowingStream<Element, Error>.Iterator {
        let (stream, continuation) = AsyncThrowingStream<Element, Error>.makeStream()
        let identifier = self.lock.withLock {
            self.lastSubscriberIdentifier += 1
            return self.lastSubscriberIdentifier
        }

        // Installed before anything can terminate the stream, so the subscriber is
        // always removed. The handler also keeps the manager alive while the
        // subscriber iterates, even after every copy of the shared sequence has
        // been released.
        continuation.onTermination = { @Sendable _ in
            self.remove(identifier)
        }

        let completion: Result<Void, Error>? = self.lock.withLock {
            if let completion = self.completion {
                return completion
            }

            self.continuations[identifier] = continuation
            return nil
        }

        if let completion {
            Self.finish(continuation, with: completion)
        } else {
            self.subscribeToBaseSequenceIfNeeded()
        }

        return stream.makeAsyncIterator()
    }

    // MARK: Sequence management

    private func remove(_ identifier: Int) {
        self.lock.withLock {
            _ = self.continuations.removeValue(forKey: identifier)
        }
    }

    private func subscribeToBaseSequenceIfNeeded() {
        self.lock.withLock {
            guard self.subscriptionTask == nil else { return }

            self.subscriptionTask = Task { [weak self, base] in
                guard !Task.isCancelled else {
                    self?.finishContinuations(with: .failure(CancellationError()))
                    return
                }

                do {
                    for try await value in base {
                        // Acquire a strong reference for the duration of a single
                        // iteration only. While suspended waiting for the next
                        // element no strong reference to the manager is held, which
                        // would otherwise form a retain cycle between the manager
                        // and this task and prevent `deinit` from ever running.
                        guard let self = self else { return }
                        self.yield(value)
                    }

                    self?.finishContinuations(with: .success(()))
                } catch {
                    self?.finishContinuations(with: .failure(error))
                }
            }
        }
    }

    // MARK: Broadcasting

    private func yield(_ element: Element) {
        let continuations = self.lock.withLock { Array(self.continuations.values) }
        for continuation in continuations {
            continuation.yield(element)
        }
    }

    private func finishContinuations(with completion: Result<Void, Error>) {
        let continuations = self.lock.withLock {
            self.completion = completion
            defer { self.continuations.removeAll() }
            return Array(self.continuations.values)
        }

        for continuation in continuations {
            Self.finish(continuation, with: completion)
        }
    }

    private static func finish(_ continuation: Continuation, with completion: Result<Void, Error>) {
        switch completion {
        case .success:
            continuation.finish()
        case .failure(let error):
            continuation.finish(throwing: error)
        }
    }
}

// MARK: Shared

extension AsyncSequence {
    /// Creates a shareable async sequence that can be used across multiple tasks.
    public func shared() -> SharedAsyncSequence<Self> where Self: Sendable, Element: Sendable {
        .init(self)
    }
}
