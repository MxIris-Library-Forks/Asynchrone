/// An asynchronous sequence that chains two async sequences, and always needs `try`.
///
/// The combined sequence first emits all the values from the first sequence
/// and then emits all values from the second.
///
/// `tryChain(with:)` returns this sequence. From macOS 15, iOS 18, tvOS 18, watchOS 11 and
/// visionOS 2 on, `chain(with:)` also returns it when either sequence can throw.
///
/// ```swift
/// let numbers = [1, 2].async
/// let moreNumbers = AsyncThrowingStream<Int, Error> { continuation in
///     continuation.yield(3)
///     continuation.finish(throwing: TestError())
/// }
///
/// do {
///     for try await value in numbers.tryChain(with: moreNumbers) {
///         print(value)
///     }
/// } catch {
///     print("Error!")
/// }
///
/// // Prints:
/// // 1
/// // 2
/// // 3
/// // Error!
/// ```
public struct ThrowingChainAsyncSequence<First: AsyncSequence, Second: AsyncSequence>: AsyncSequence
where First.Element == Second.Element {
    /// The kind of elements streamed.
    public typealias Element = First.Element

    // Private
    private let first: First
    private let second: Second

    // MARK: Initialization

    /// Creates an async sequence that combines the two async sequences.
    /// - Parameters:
    ///   - first: The first async sequence.
    ///   - second: The second async sequence.
    init(
        _ first: First,
        _ second: Second
    ) {
        self.first = first
        self.second = second
    }

    // MARK: AsyncSequence

    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> Iterator {
        Iterator(self.first.makeAsyncIterator(), self.second)
    }
}

extension ThrowingChainAsyncSequence: Sendable
where
First: Sendable,
Second: Sendable {}

// MARK: Iterator

extension ThrowingChainAsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var firstIterator: First.AsyncIterator
        private let second: Second
        // Made once the first sequence finishes, so that the second one does not
        // start producing elements (or side effects) any earlier.
        private var secondIterator: Second.AsyncIterator?

        // MARK: Initialization

        init(
            _ firstIterator: First.AsyncIterator,
            _ second: Second
        ) {
            self.firstIterator = firstIterator
            self.second = second
        }

        // MARK: AsyncIteratorProtocol

        /// Produces the next element in the sequence.
        ///
        /// Emits the elements of the first sequence, then those of the second one.
        /// - Returns: The next element or `nil` if the end of the sequence is reached.
        public mutating func next() async throws -> Element? {
            if self.secondIterator == nil {
                if let element = try await self.firstIterator.next() {
                    return element
                }

                self.secondIterator = self.second.makeAsyncIterator()
            }

            return try await self.secondIterator?.next()
        }
    }
}

extension ThrowingChainAsyncSequence.Iterator: Sendable
where
First.AsyncIterator: Sendable,
Second: Sendable,
Second.AsyncIterator: Sendable {}

// MARK: Chain

extension AsyncSequence {
    // Without OS versions, the obsoleted `rethrows` overload stays visible next to this one,
    // and a call with a sequence that can throw would be ambiguous between them.
    #if canImport(Darwin)
    /// An asynchronous sequence that chains two async sequences, at least one of which can throw.
    ///
    /// The combined sequence first emits all the values from the first sequence
    /// and then emits all values from the second. Iterating it needs `try`.
    ///
    /// When neither sequence can throw, `chain(with:)` picks the overload that returns a
    /// `ChainAsyncSequence` instead, and iterating it needs no `try`.
    ///
    /// ```swift
    /// let numbers = [1, 2].async
    /// let moreNumbers = AsyncThrowingStream<Int, Error> { continuation in
    ///     continuation.yield(3)
    ///     continuation.finish()
    /// }
    ///
    /// for try await value in numbers.chain(with: moreNumbers) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // 1
    /// // 2
    /// // 3
    /// ```
    /// - Parameter other: The async sequence to iterate through after this one.
    /// - Returns: An async sequence that chains the two sequences.
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func chain<Other: AsyncSequence>(with other: Other) -> ThrowingChainAsyncSequence<Self, Other> {
        .init(self, other)
    }
    #endif

    /// An asynchronous sequence that chains two async sequences, and always needs `try`.
    ///
    /// It behaves like `chain(with:)`, but never picks an overload that needs no `try`. Use it
    /// below macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2, where `chain(with:)` lets
    /// this sequence alone decide whether `try` is needed: if this sequence never throws and
    /// `other` does, `collect()`, `first()` and the other `rethrows` methods compile without
    /// `try` there, and the error is lost.
    ///
    /// ```swift
    /// let numbers = [1, 2].async
    /// let moreNumbers = AsyncThrowingStream<Int, Error> { continuation in
    ///     continuation.yield(3)
    ///     continuation.finish(throwing: TestError())
    /// }
    ///
    /// do {
    ///     for try await value in numbers.tryChain(with: moreNumbers) {
    ///         print(value)
    ///     }
    /// } catch {
    ///     print("Error!")
    /// }
    ///
    /// // Prints:
    /// // 1
    /// // 2
    /// // 3
    /// // Error!
    /// ```
    /// - Parameter other: The async sequence to iterate through after this one.
    /// - Returns: An async sequence that chains the two sequences.
    public func tryChain<Other: AsyncSequence>(with other: Other) -> ThrowingChainAsyncSequence<Self, Other> {
        .init(self, other)
    }
}
