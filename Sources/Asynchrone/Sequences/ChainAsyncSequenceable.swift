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
    ///
    /// - Important: This overload is used below macOS 15, iOS 18, tvOS 18, watchOS 11 and
    ///   visionOS 2. There, this sequence alone decides whether the chained sequence throws:
    ///   if this sequence never throws and `sequence` does, `collect()`, `first()` and the
    ///   other `rethrows` methods compile without `try`, and the error from `sequence` is
    ///   lost. Use `tryChain(with:)` in that case. From those versions on, `chain(with:)`
    ///   needs no `try` only when neither sequence can throw.
    /// - Parameters:
    ///   - lhs: The first async sequence to iterate through.
    ///   - rhs: The second async sequence to iterate through.
    /// - Returns: A async sequence chains the two sequences.
    @available(macOS, obsoleted: 15)
    @available(iOS, obsoleted: 18)
    @available(macCatalyst, obsoleted: 18)
    @available(tvOS, obsoleted: 18)
    @available(watchOS, obsoleted: 11)
    @available(visionOS, obsoleted: 2)
    public func chain<P>(with sequence: P) -> ChainAsyncSequence<Self, P> where P: AsyncSequence {
        .init(self, sequence)
    }

    /// An asynchronous sequence that chains two async sequences that never throw.
    ///
    /// The combined sequence first emits all the values from the first sequence
    /// and then emits all values from the second.
    ///
    /// When either sequence can throw, `chain(with:)` picks the overload that returns a
    /// `ThrowingChainAsyncSequence` instead, and iterating it needs `try`.
    ///
    /// ```swift
    /// for await value in [1, 2].async.chain(with: [3, 4].async) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // 1
    /// // 2
    /// // 3
    /// // 4
    /// ```
    /// - Parameter other: The async sequence to iterate through after this one.
    /// - Returns: An async sequence that chains the two sequences.
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func chain<Other: AsyncSequence>(
        with other: Other
    ) -> ChainAsyncSequence<Self, Other> where Failure == Never, Other.Failure == Never {
        .init(self, other)
    }
}
