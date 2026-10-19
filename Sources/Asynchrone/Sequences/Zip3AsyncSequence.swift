/// An asynchronous sequence that applys a zip function to the three async sequences.
///
/// Use `Zip3AsyncSequence` to combine the latest elements from three async sequcnes and emit a tuple.
///
/// The async sequence waits until both provided async sequences have emitted an element,
/// then emits both elements as a tuple.
///
/// If one sequence never emits a value or raises an error then the zipped sequence will finish.
///
/// ```swift
/// let streamA = .init { continuation in
///     continuation.yield(1)
///     continuation.yield(2)
///     continuation.finish()
/// }
///
/// let streamB = .init { continuation in
///     continuation.yield(5)
///     continuation.yield(6)
///     continuation.yield(7)
///     continuation.finish()
/// }
///
/// let streamC = .init { continuation in
///     continuation.yield(8)
///     continuation.yield(9)
///     continuation.finish()
/// }
///
/// for await value in streamA.zip(streamB, streamC) {
///     print(value)
/// }
///
/// // Prints:
/// // (1, 5, 8)
/// // (2, 6, 9)
/// ```
public struct Zip3AsyncSequence<P: AsyncSequence, Q: AsyncSequence, R: AsyncSequence>: AsyncSequence {
    /// The kind of elements streamed.
    public typealias Element = (P.Element, Q.Element, R.Element)
    
    // Private
    private let p: P
    private let q: Q
    private let r: R

    // MARK: Initialization

    /// Creates an async sequence that zips and emits the elements from the provided async sequences.
    /// - Parameters:
    ///   - p: An async sequence.
    ///   - q: An async sequence.
    ///   - r: An async sequence.
    init(
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
        Iterator(self.p.makeAsyncIterator(), self.q.makeAsyncIterator(), self.r.makeAsyncIterator())
    }
}

extension Zip3AsyncSequence: Sendable
where
P: Sendable,
Q: Sendable,
R: Sendable {}

// MARK: Iterator

extension Zip3AsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iteratorP: P.AsyncIterator
        private var iteratorQ: Q.AsyncIterator
        private var iteratorR: R.AsyncIterator

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
        /// Continues to call `next()` on it's base iterator and iterator of
        /// it's combined sequence.
        ///
        /// If any iterator returns `nil`, indicating the end of the sequence, this
        /// iterator returns `nil`.
        /// - Returns: The next element or `nil` if the end of the sequence is reached.
        public mutating func next() async rethrows -> Element? {
            // If any sequence reaches the end, then this sequence finishes
            // without awaiting the remaining iterators.
            guard let elementP = try await self.iteratorP.next() else { return nil }
            guard let elementQ = try await self.iteratorQ.next() else { return nil }
            guard let elementR = try await self.iteratorR.next() else { return nil }

            return (elementP, elementQ, elementR)
        }
    }
}

extension Zip3AsyncSequence.Iterator: Sendable
where
P.AsyncIterator: Sendable,
Q.AsyncIterator: Sendable,
R.AsyncIterator: Sendable {}

// MARK: Zip

extension AsyncSequence {
    /// Create an asynchronous sequence that applys a zip function to the three async sequences.
    ///
    /// Combines the latest elements from three async sequences and emits a tuple.
    ///
    /// The async sequence waits until both provided async sequences have emitted an element,
    /// then emits both elements as a tuple.
    ///
    /// If one sequence never emits a value or raises an error then the zipped sequence will finish.
    ///
    /// ```swift
    /// let streamA = .init { continuation in
    ///     continuation.yield(1)
    ///     continuation.yield(2)
    ///     continuation.finish()
    /// }
    ///
    /// let streamB = .init { continuation in
    ///     continuation.yield(5)
    ///     continuation.yield(6)
    ///     continuation.yield(7)
    ///     continuation.finish()
    /// }
    ///
    /// let streamC = .init { continuation in
    ///     continuation.yield(8)
    ///     continuation.yield(9)
    ///     continuation.finish()
    /// }
    ///
    /// for await value in streamA.zip(streamB, streamC) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // (1, 5, 8)
    /// // (2, 6, 9)
    /// ```
    /// - Parameters:
    ///   - q: Another async sequence.
    ///   - r: Another async sequence.
    /// - Returns: A async sequence zips elements from this and another async sequence.
    public func zip<Q, R>(
        _ q: Q,
        _ r: R
    ) -> Zip3AsyncSequence<Self, Q, R> where Q: AsyncSequence, R: AsyncSequence {
        .init(self, q, r)
    }
}
