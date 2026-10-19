/// An asynchronous sequence that applys a zip function to the two async sequences.
///
/// Use `ZipAsyncSequence` to combine the latest elements from two async sequences and emit a tuple.
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
/// for await value in streamA.zip(streamB) {
///     print(value)
/// }
///
/// // Prints:
/// // (1, 5)
/// // (2, 6)
/// ```
public struct ZipAsyncSequence<P: AsyncSequence, Q: AsyncSequence>: AsyncSequence {
    /// The kind of elements streamed.
    public typealias Element = (P.Element, Q.Element)
    
    // Private
    private let p: P
    private let q: Q

    // MARK: Initialization

    /// Creates an async sequence that zips and emits the elements from the provided async sequences.
    /// - Parameters:
    ///   - p: An async sequence.
    ///   - q: An async sequence.
    init(
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

extension ZipAsyncSequence: Sendable
where
P: Sendable,
Q: Sendable {}

// MARK: Iterator

extension ZipAsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iteratorP: P.AsyncIterator
        private var iteratorQ: Q.AsyncIterator

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

            return (elementP, elementQ)
        }
    }
}

extension ZipAsyncSequence.Iterator: Sendable
where
P.AsyncIterator: Sendable,
Q.AsyncIterator: Sendable {}

// MARK: Zip

extension AsyncSequence {
    /// Create an asynchronous sequence that applys a zip function to the two async sequences.
    ///
    /// Combines the latest elements from two async sequences and emits a tuple.
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
    /// for await value in streamA.zip(streamB) {
    ///     print(value)
    /// }
    ///
    /// // Prints:
    /// // (1, 5)
    /// // (2, 6)
    /// ```
    ///
    /// - Important: This overload is used below macOS 15, iOS 18, tvOS 18, watchOS 11 and
    ///   visionOS 2. There, this sequence alone decides whether the zipped sequence throws: if
    ///   this sequence never throws and `other` does, `collect()`, `first()` and the other
    ///   `rethrows` methods compile without `try`, and the error from `other` is lost. Use
    ///   `tryZip(_:_:)` in that case. From those versions on, `zip(_:)` needs no `try` only
    ///   when neither sequence can throw.
    /// - Parameters:
    ///   - other: Another async sequence to zip with.
    /// - Returns: A async sequence zips elements from this and another async sequence.
    @available(macOS, obsoleted: 15)
    @available(iOS, obsoleted: 18)
    @available(macCatalyst, obsoleted: 18)
    @available(tvOS, obsoleted: 18)
    @available(watchOS, obsoleted: 11)
    @available(visionOS, obsoleted: 2)
    public func zip<Q>(
        _ other: Q
    ) -> ZipAsyncSequence<Self, Q> where Q: AsyncSequence {
        .init(self, other)
    }

    /// Creates an asynchronous sequence that zips two async sequences that never throw.
    ///
    /// The async sequence waits until both provided async sequences have emitted an element,
    /// then emits both elements as a tuple. Once one of the sequences finishes, the zipped
    /// sequence finishes.
    ///
    /// When either sequence can throw, `zip(_:)` picks the overload that returns a
    /// `ThrowingZipAsyncSequence` instead, and iterating it needs `try`.
    ///
    /// ```swift
    /// for await (number, word) in [1, 2].async.zip(["one", "two", "three"].async) {
    ///     print(number, word)
    /// }
    ///
    /// // Prints:
    /// // 1 one
    /// // 2 two
    /// ```
    /// - Parameters:
    ///   - other: Another async sequence to zip with.
    /// - Returns: An async sequence that zips the elements of this and the other async sequence.
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
    public func zip<Other: AsyncSequence>(
        _ other: Other
    ) -> ZipAsyncSequence<Self, Other> where Failure == Never, Other.Failure == Never {
        .init(self, other)
    }
}
