/// An asynchronous sequence that combines three async sequences.
///
/// The combined sequence emits a tuple of the most-recent elements from each sequence
/// when any of them emit a value.
///
/// The first tuple is emitted once all sequences have emitted at least one element.
/// If one sequence finishes after having emitted at least one element, its last element
/// is used for subsequent combinations. If one sequence finishes without ever emitting
/// an element, the combined sequence finishes immediately.
///
/// ```swift
/// let streamA = AsyncStream<Int> { continuation in
///     continuation.yield(1)
///     try? await Task.sleep(seconds: 0.3)
///     continuation.yield(2)
///     continuation.finish()
/// }
///
/// let streamB = AsyncStream<Int> { continuation in
///     try? await Task.sleep(seconds: 0.1)
///     continuation.yield(5)
///     continuation.finish()
/// }
///
/// let streamC = AsyncStream<Int> { continuation in
///     try? await Task.sleep(seconds: 0.2)
///     continuation.yield(10)
///     continuation.finish()
/// }
///
/// for await value in streamA.combineLatest(streamB, streamC) {
///     print(value)
/// }
///
/// // Prints:
/// // (1, 5, 10)
/// // (2, 5, 10)
/// ```
public struct CombineLatest3AsyncSequence<P: AsyncSequence, Q: AsyncSequence, R: AsyncSequence>: AsyncSequence, Sendable
where
P: Sendable,
P.AsyncIterator: Sendable,
P.Element: Sendable,
Q: Sendable,
Q.AsyncIterator: Sendable,
Q.Element: Sendable,
R: Sendable,
R.AsyncIterator: Sendable,
R.Element: Sendable {
    /// The kind of elements streamed.
    public typealias Element = (P.Element, Q.Element, R.Element)

    // Private
    private let p: P
    private let q: Q
    private let r: R

    // MARK: Initialization

    /// Creates an async sequence that combines the three provided async sequences.
    /// - Parameters:
    ///   - p: An async sequence.
    ///   - q: An async sequence.
    ///   - r: An async sequence.
    public init(
        _ p: P,
        _ q: Q,
        _ r: R
    ) {
        self.p = p
        self.q = q
        self.r = r
    }

    // MARK: AsyncSequence

    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            self.p.makeAsyncIterator(),
            self.q.makeAsyncIterator(),
            self.r.makeAsyncIterator()
        )
    }
}

// MARK: Iterator

extension CombineLatest3AsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iteratorP: P.AsyncIterator
        private var iteratorQ: Q.AsyncIterator
        private var iteratorR: R.AsyncIterator

        private var latestElementP: P.Element?
        private var latestElementQ: Q.Element?
        private var latestElementR: R.Element?

        private var isFinishedP = false
        private var isFinishedQ = false
        private var isFinishedR = false

        private var pendingTaskP: Task<RaceWinner, Never>?
        private var pendingTaskQ: Task<RaceWinner, Never>?
        private var pendingTaskR: Task<RaceWinner, Never>?

        // MARK: Initialization

        init(
            _ iteratorP: P.AsyncIterator,
            _ iteratorQ: Q.AsyncIterator,
            _ iteratorR: R.AsyncIterator
        ) {
            self.iteratorP = iteratorP
            self.iteratorQ = iteratorQ
            self.iteratorR = iteratorR
        }

        // MARK: AsyncIteratorProtocol

        /// Produces the next element in the sequence.
        ///
        /// Races all base iterators and emits a tuple of the most-recent elements
        /// whenever any of them produces a new element.
        /// - Returns: The next element or `nil` if the end of the sequence is reached.
        public mutating func next() async rethrows -> Element? {
            while true {
                if self.isFinishedP && self.isFinishedQ && self.isFinishedR {
                    return nil
                }

                var racingTasks: [Task<RaceWinner, Never>] = []

                if !self.isFinishedP {
                    let task = self.pendingTaskP ?? Task { [iteratorP] in
                        var iterator = iteratorP
                        do {
                            let element = try await iterator.next()
                            return .p(.success(element), iterator: iterator)
                        } catch {
                            return .p(.failure(error), iterator: iterator)
                        }
                    }
                    self.pendingTaskP = task
                    racingTasks.append(task)
                }

                if !self.isFinishedQ {
                    let task = self.pendingTaskQ ?? Task { [iteratorQ] in
                        var iterator = iteratorQ
                        do {
                            let element = try await iterator.next()
                            return .q(.success(element), iterator: iterator)
                        } catch {
                            return .q(.failure(error), iterator: iterator)
                        }
                    }
                    self.pendingTaskQ = task
                    racingTasks.append(task)
                }

                if !self.isFinishedR {
                    let task = self.pendingTaskR ?? Task { [iteratorR] in
                        var iterator = iteratorR
                        do {
                            let element = try await iterator.next()
                            return .r(.success(element), iterator: iterator)
                        } catch {
                            return .r(.failure(error), iterator: iterator)
                        }
                    }
                    self.pendingTaskR = task
                    racingTasks.append(task)
                }

                let firstTask = await Task.firstToComplete(of: racingTasks)

                // The losing tasks stay in their pending slots and re-enter the race
                // on the next loop iteration, so no element is ever dropped.
                switch await firstTask.value {
                case .p(let result, let iterator):
                    self.pendingTaskP = nil
                    self.iteratorP = iterator

                    switch result {
                    case .success(.some(let element)):
                        self.latestElementP = element
                        if let latestElementQ = self.latestElementQ,
                           let latestElementR = self.latestElementR {
                            return (element, latestElementQ, latestElementR)
                        }
                    case .success(.none):
                        self.isFinishedP = true
                        if self.latestElementP == nil {
                            // P finished without ever emitting an element so
                            // no combined element can ever be produced.
                            self.finish()
                            return nil
                        }
                    case .failure:
                        self.finish()
                        try result._rethrowError()
                    }
                case .q(let result, let iterator):
                    self.pendingTaskQ = nil
                    self.iteratorQ = iterator

                    switch result {
                    case .success(.some(let element)):
                        self.latestElementQ = element
                        if let latestElementP = self.latestElementP,
                           let latestElementR = self.latestElementR {
                            return (latestElementP, element, latestElementR)
                        }
                    case .success(.none):
                        self.isFinishedQ = true
                        if self.latestElementQ == nil {
                            // Q finished without ever emitting an element so
                            // no combined element can ever be produced.
                            self.finish()
                            return nil
                        }
                    case .failure:
                        self.finish()
                        try result._rethrowError()
                    }
                case .r(let result, let iterator):
                    self.pendingTaskR = nil
                    self.iteratorR = iterator

                    switch result {
                    case .success(.some(let element)):
                        self.latestElementR = element
                        if let latestElementP = self.latestElementP,
                           let latestElementQ = self.latestElementQ {
                            return (latestElementP, latestElementQ, element)
                        }
                    case .success(.none):
                        self.isFinishedR = true
                        if self.latestElementR == nil {
                            // R finished without ever emitting an element so
                            // no combined element can ever be produced.
                            self.finish()
                            return nil
                        }
                    case .failure:
                        self.finish()
                        try result._rethrowError()
                    }
                }
            }
        }

        private mutating func finish() {
            self.isFinishedP = true
            self.isFinishedQ = true
            self.isFinishedR = true
            self.pendingTaskP?.cancel()
            self.pendingTaskP = nil
            self.pendingTaskQ?.cancel()
            self.pendingTaskQ = nil
            self.pendingTaskR?.cancel()
            self.pendingTaskR = nil
        }
    }
}

extension CombineLatest3AsyncSequence.Iterator: Sendable {}

// MARK: Race winner

extension CombineLatest3AsyncSequence.Iterator {
    fileprivate enum RaceWinner {
        case p(Result<P.Element?, Error>, iterator: P.AsyncIterator)
        case q(Result<Q.Element?, Error>, iterator: Q.AsyncIterator)
        case r(Result<R.Element?, Error>, iterator: R.AsyncIterator)
    }
}

// MARK: Combine latest

extension AsyncSequence where Self: Sendable, AsyncIterator: Sendable, Element: Sendable {
    /// Combine three async sequences.
    ///
    /// The combined sequence emits a tuple of the most-recent elements from each sequence
    /// when any of them emit a value.
    ///
    /// The first tuple is emitted once all sequences have emitted at least one element.
    /// If one sequence finishes after having emitted at least one element, its last element
    /// is used for subsequent combinations. If one sequence finishes without ever emitting
    /// an element, the combined sequence finishes immediately.
    ///
    /// ```swift
    /// let streamA = AsyncStream<Int> { continuation in
    ///     continuation.yield(1)
    ///     try? await Task.sleep(seconds: 0.3)
    ///     continuation.yield(2)
    ///     continuation.finish()
    /// }
    ///
    /// let streamB = AsyncStream<Int> { continuation in
    ///     try? await Task.sleep(seconds: 0.1)
    ///     continuation.yield(5)
    ///     continuation.finish()
    /// }
    ///
    /// let streamC = AsyncStream<Int> { continuation in
    ///     try? await Task.sleep(seconds: 0.2)
    ///     continuation.yield(10)
    ///     continuation.finish()
    /// }
    ///
    /// for await value in streamA.combineLatest(streamB, streamC) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // (1, 5, 10)
    /// // (2, 5, 10)
    /// ```
    /// - Parameters:
    ///   - q: Another async sequence to combine with.
    ///   - r: Another async sequence to combine with.
    /// - Returns: A async sequence combines elements from all sequences.
    public func combineLatest<Q, R>(
        _ q: Q,
        _ r: R
    ) -> CombineLatest3AsyncSequence<Self, Q, R>
    where
    Q: AsyncSequence, Q: Sendable, Q.AsyncIterator: Sendable, Q.Element: Sendable,
    R: AsyncSequence, R: Sendable, R.AsyncIterator: Sendable, R.Element: Sendable {
        .init(self, q, r)
    }
}
