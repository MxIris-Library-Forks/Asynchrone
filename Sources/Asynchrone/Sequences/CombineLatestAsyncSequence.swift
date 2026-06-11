/// An asynchronous sequence that combines two async sequences.
///
/// The combined sequence emits a tuple of the most-recent elements from each sequence
/// when any of them emit a value.
///
/// The first tuple is emitted once both sequences have emitted at least one element.
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
///     try? await Task.sleep(seconds: 0.1)
///     continuation.yield(6)
///     continuation.finish()
/// }
///
/// for await value in streamA.combineLatest(streamB) {
///     print(value)
/// }
///
/// // Prints:
/// // (1, 5)
/// // (1, 6)
/// // (2, 6)
/// ```
public struct CombineLatestAsyncSequence<P: AsyncSequence, Q: AsyncSequence>: AsyncSequence, Sendable
where
P: Sendable,
P.AsyncIterator: Sendable,
P.Element: Sendable,
Q: Sendable,
Q.AsyncIterator: Sendable,
Q.Element: Sendable {
    /// The kind of elements streamed.
    public typealias Element = (P.Element, Q.Element)

    // Private
    private let p: P
    private let q: Q

    // MARK: Initialization

    /// Creates an async sequence that combines the two provided async sequences.
    /// - Parameters:
    ///   - p: An async sequence.
    ///   - q: An async sequence.
    public init(
        _ p: P,
        _ q: Q
    ) {
        self.p = p
        self.q = q
    }

    // MARK: AsyncSequence

    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> Iterator {
        Iterator(self.p.makeAsyncIterator(), self.q.makeAsyncIterator())
    }
}

// MARK: Iterator

extension CombineLatestAsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iteratorP: P.AsyncIterator
        private var iteratorQ: Q.AsyncIterator

        private var latestElementP: P.Element?
        private var latestElementQ: Q.Element?

        private var isFinishedP = false
        private var isFinishedQ = false

        private var pendingTaskP: Task<RaceWinner, Never>?
        private var pendingTaskQ: Task<RaceWinner, Never>?

        // MARK: Initialization

        init(
            _ iteratorP: P.AsyncIterator,
            _ iteratorQ: Q.AsyncIterator
        ) {
            self.iteratorP = iteratorP
            self.iteratorQ = iteratorQ
        }

        // MARK: AsyncIteratorProtocol

        /// Produces the next element in the sequence.
        ///
        /// Races both base iterators and emits a tuple of the most-recent elements
        /// whenever either of them produces a new element.
        /// - Returns: The next element or `nil` if the end of the sequence is reached.
        public mutating func next() async rethrows -> Element? {
            while true {
                if self.isFinishedP && self.isFinishedQ {
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

                let firstTask = await Task.firstToComplete(of: racingTasks)

                // The losing task stays in its pending slot and re-enters the race
                // on the next loop iteration, so no element is ever dropped.
                switch await firstTask.value {
                case .p(let result, let iterator):
                    self.pendingTaskP = nil
                    self.iteratorP = iterator

                    switch result {
                    case .success(.some(let element)):
                        self.latestElementP = element
                        if let latestElementQ = self.latestElementQ {
                            return (element, latestElementQ)
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
                        if let latestElementP = self.latestElementP {
                            return (latestElementP, element)
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
                }
            }
        }

        private mutating func finish() {
            self.isFinishedP = true
            self.isFinishedQ = true
            self.pendingTaskP?.cancel()
            self.pendingTaskP = nil
            self.pendingTaskQ?.cancel()
            self.pendingTaskQ = nil
        }
    }
}

extension CombineLatestAsyncSequence.Iterator: Sendable {}

// MARK: Race winner

extension CombineLatestAsyncSequence.Iterator {
    fileprivate enum RaceWinner {
        case p(Result<P.Element?, Error>, iterator: P.AsyncIterator)
        case q(Result<Q.Element?, Error>, iterator: Q.AsyncIterator)
    }
}

// MARK: Combine latest

extension AsyncSequence where Self: Sendable, AsyncIterator: Sendable, Element: Sendable {
    /// Combine with an additional async sequence to produce a `CombineLatestAsyncSequence`.
    ///
    /// The combined sequence emits a tuple of the most-recent elements from each sequence
    /// when any of them emit a value.
    ///
    /// The first tuple is emitted once both sequences have emitted at least one element.
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
    ///     try? await Task.sleep(seconds: 0.1)
    ///     continuation.yield(6)
    ///     continuation.finish()
    /// }
    ///
    /// for await value in streamA.combineLatest(streamB) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // (1, 5)
    /// // (1, 6)
    /// // (2, 6)
    /// ```
    /// - Parameters:
    ///   - other: Another async sequence to combine with.
    /// - Returns: A async sequence combines elements from this and another async sequence.
    public func combineLatest<Q>(
        _ other: Q
    ) -> CombineLatestAsyncSequence<Self, Q>
    where Q: AsyncSequence, Q: Sendable, Q.AsyncIterator: Sendable, Q.Element: Sendable {
        .init(self, other)
    }
}
