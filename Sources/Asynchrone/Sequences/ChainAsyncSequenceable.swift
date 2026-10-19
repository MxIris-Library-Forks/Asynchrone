/// An asynchronous sequence that chains two async sequences.
///
/// The combined sequence first emits the all the values from the first sequence
/// and then emits all values from the second.
///
/// ```swift
/// let sequenceA = AsyncStream<Int> { continuation in
///     continuation.yield(1)
///     continuation.yield(2)
///     continuation.yield(3)
///     continuation.finish()
/// }
///
/// let sequenceB = AsyncStream<Int> { continuation in
///     continuation.yield(4)
///     continuation.yield(5)
///     continuation.yield(6)
///     continuation.finish()
/// }
///
/// let sequenceC = AsyncStream<Int> { continuation in
///     continuation.yield(7)
///     continuation.yield(8)
///     continuation.yield(9)
///     continuation.finish()
/// }
///
/// for await value in sequenceA.chain(with: sequenceB).chain(with: sequenceC) {
///     print(value)
/// }
///
/// // Prints:
/// // 1
/// // 2
/// // 3
/// // 4
/// // 5
/// // 6
/// // 7
/// // 8
/// // 9
/// ```
public struct ChainAsyncSequence<P: AsyncSequence, Q: AsyncSequence>: AsyncSequence where P.Element == Q.Element {
    /// The kind of elements streamed.
    public typealias Element = P.Element
    
    // Private
    private let p: P
    private let q: Q

    // MARK: Initialization

    /// Creates an async sequence that combines the two async sequence.
    /// - Parameters:
    ///   - p: The first async sequence.
    ///   - q: The second async sequence.
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
        Iterator(self.p.makeAsyncIterator(), self.q)
    }
}

extension ChainAsyncSequence: Sendable
where
P: Sendable,
Q: Sendable {}

// MARK: Iterator

extension ChainAsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iteratorP: P.AsyncIterator
        private let q: Q
        // Made once the first sequence finishes, so that the second one does not
        // start producing elements (or side effects) any earlier.
        private var iteratorQ: Q.AsyncIterator?

        // MARK: Initialization

        init(
            _ iteratorP: P.AsyncIterator,
            _ q: Q
        ) {
            self.iteratorP = iteratorP
            self.q = q
        }

        // MARK: AsyncIteratorProtocol

        public mutating func next() async rethrows -> Element? {
            if self.iteratorQ == nil {
                if let element = try await self.iteratorP.next() {
                    return element
                }

                self.iteratorQ = self.q.makeAsyncIterator()
            }

            return try await self.iteratorQ?.next()
        }
    }
}

extension ChainAsyncSequence.Iterator: Sendable
where
P.AsyncIterator: Sendable,
Q: Sendable,
Q.AsyncIterator: Sendable {}

// MARK: Chain

extension AsyncSequence {
    /// An asynchronous sequence that chains two async sequences.
    ///
    /// The combined sequence first emits the all the values from the first sequence
    /// and then emits all values from the second.
    ///
    /// ```swift
    /// let sequenceA = AsyncStream<Int> { continuation in
    ///     continuation.yield(1)
    ///     continuation.yield(2)
    ///     continuation.yield(3)
    ///     continuation.finish()
    /// }
    ///
    /// let sequenceB = AsyncStream<Int> { continuation in
    ///     continuation.yield(4)
    ///     continuation.yield(5)
    ///     continuation.yield(6)
    ///     continuation.finish()
    /// }
    ///
    /// let sequenceC = AsyncStream<Int> { continuation in
    ///     continuation.yield(7)
    ///     continuation.yield(8)
    ///     continuation.yield(9)
    ///     continuation.finish()
    /// }
    ///
    /// for await value in sequenceA.chain(with: sequenceB).chain(with: sequenceC) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // 1
    /// // 2
    /// // 3
    /// // 4
    /// // 5
    /// // 6
    /// // 7
    /// // 8
    /// // 9
    /// ```
    /// - Parameters:
    ///   - lhs: The first async sequence to iterate through.
    ///   - rhs: The second async sequence to iterate through.
    /// - Returns: A async sequence chains the two sequences.
    public func chain<P>(with sequence: P) -> ChainAsyncSequence<Self, P> where P: AsyncSequence {
        .init(self, sequence)
    }
}
