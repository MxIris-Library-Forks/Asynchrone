/// An asynchronous sequence that zips any number of async sequences, and always needs `try`.
///
/// Use `zip(_:_:)` to zip four or more sequences, or `tryZip(_:_:)` to zip any number of
/// them. From macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2 on, `zip(_:)` and
/// `zip(_:_:)` also return this sequence for two or three sequences when any of them can throw.
///
/// The async sequence waits until every provided async sequence has emitted an element,
/// then emits the elements as a tuple. The sequences are advanced in order: once one of them
/// finishes, the sequences after it are not advanced, and the zipped sequence finishes. The
/// first error ends the zipped sequence and is rethrown.
///
/// ```swift
/// let numbers = [1, 2, 3].async
/// let words = ["one", "two"].async
/// let flags = [true, false, true].async
/// let letters = ["a", "b", "c"].async
///
/// for try await (number, word, flag, letter) in numbers.zip(words, flags, letters) {
///     print(number, word, flag, letter)
/// }
///
/// // Prints:
/// // 1 one true a
/// // 2 two false b
/// ```
///
/// The generic parameters are tuples with one member per zipped sequence: `Bases` holds the
/// sequences, `Iterators` their iterators and `Element` their elements.
public struct ThrowingZipAsyncSequence<Bases, Iterators, Element>: AsyncSequence {
    // Private
    private let bases: Bases
    private let makeIterators: @Sendable (Bases) -> Iterators
    private let advance: @Sendable (inout Iterators) async throws -> Element?

    // MARK: Initialization

    fileprivate init(
        bases: Bases,
        makeIterators: @escaping @Sendable (Bases) -> Iterators,
        advance: @escaping @Sendable (inout Iterators) async throws -> Element?
    ) {
        self.bases = bases
        self.makeIterators = makeIterators
        self.advance = advance
    }

    // MARK: AsyncSequence

    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> Iterator {
        Iterator(iterators: self.makeIterators(self.bases), advance: self.advance)
    }
}

extension ThrowingZipAsyncSequence: Sendable where Bases: Sendable {}

// MARK: Iterator

extension ThrowingZipAsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iterators: Iterators
        private let advance: @Sendable (inout Iterators) async throws -> Element?
        private var isFinished = false

        // MARK: Initialization

        fileprivate init(
            iterators: Iterators,
            advance: @escaping @Sendable (inout Iterators) async throws -> Element?
        ) {
            self.iterators = iterators
            self.advance = advance
        }

        // MARK: AsyncIteratorProtocol

        /// Produces the next element in the sequence.
        ///
        /// Advances the iterators of the zipped sequences in order. If any of them returns `nil`
        /// or throws, the iterators after it are not advanced, and this iterator finishes.
        /// - Returns: The next element or `nil` if the end of the sequence is reached.
        public mutating func next() async throws -> Element? {
            guard !self.isFinished else { return nil }

            do {
                guard let element = try await self.advance(&self.iterators) else {
                    self.isFinished = true
                    return nil
                }

                return element
            } catch {
                // The iterators that the failed round advanced were copies, so going on
                // would emit their elements a second time.
                self.isFinished = true
                throw error
            }
        }
    }
}

extension ThrowingZipAsyncSequence.Iterator: Sendable where Iterators: Sendable {}

// MARK: Making the sequence

/// Thrown by `advanced(_:)` when an iterator finishes, so that the iterators after it are not advanced.
private struct EndOfZippedSequence: Error {}

/// Advances a copy of `iterator`.
///
/// The iterators live in a tuple whose type is a pack expansion, and a member of such a
/// tuple cannot be mutated in place. So each round copies every iterator out, advances the
/// copy, and writes all of them back.
private func advanced<Iterator: AsyncIteratorProtocol>(
    _ iterator: Iterator
) async throws -> (iterator: Iterator, element: Iterator.Element) {
    var iterator = iterator
    guard let element = try await iterator.next() else {
        throw EndOfZippedSequence()
    }

    return (iterator, element)
}

/// Makes the sequence that zips `bases`.
///
/// The sequence type has no parameter pack, because a generic type with one needs macOS 14,
/// iOS 17, tvOS 17 or watchOS 10, while a function with one runs on every system the package
/// supports. So the pack lives only in this function and in the two closures it makes.
private func makeThrowingZip<each Base: AsyncSequence>(
    _ bases: repeat each Base
) -> ThrowingZipAsyncSequence<
    (repeat each Base),
    (repeat (each Base).AsyncIterator),
    (repeat (each Base).Element)
> {
    ThrowingZipAsyncSequence(
        bases: (repeat each bases),
        makeIterators: { bases in
            (repeat (each bases).makeAsyncIterator())
        },
        advance: { iterators in
            do {
                let results = (repeat try await advanced(each iterators))
                iterators = (repeat (each results).iterator)
                return (repeat (each results).element)
            } catch is EndOfZippedSequence {
                return nil
            }
        }
    )
}

// MARK: Zip

extension AsyncSequence {
    /// Creates an asynchronous sequence that zips this async sequence with any number of others.
    ///
    /// The async sequence waits until every provided async sequence has emitted an element,
    /// then emits the elements as a tuple. Once one of the sequences finishes, the zipped
    /// sequence finishes. The first error ends the zipped sequence and is rethrown.
    ///
    /// Iterating the zipped sequence always needs `try`. From macOS 15, iOS 18, tvOS 18,
    /// watchOS 11 and visionOS 2 on, zipping two or three sequences that never throw picks an
    /// overload that needs no `try`. Below those versions, two or three sequences pick
    /// overloads that let the first sequence alone decide whether `try` is needed; use
    /// `tryZip(_:_:)` there when a later sequence can throw.
    ///
    /// ```swift
    /// let numbers = [1, 2, 3].async
    /// let words = ["one", "two"].async
    /// let flags = [true, false, true].async
    /// let letters = ["a", "b", "c"].async
    ///
    /// for try await (number, word, flag, letter) in numbers.zip(words, flags, letters) {
    ///     print(number, word, flag, letter)
    /// }
    ///
    /// // Prints:
    /// // 1 one true a
    /// // 2 two false b
    /// ```
    /// - Parameters:
    ///   - second: The second async sequence to zip.
    ///   - remaining: Any further async sequences to zip.
    /// - Returns: An async sequence that zips the elements of this and the other async sequences.
    public func zip<Second: AsyncSequence, each Remaining: AsyncSequence>(
        _ second: Second,
        _ remaining: repeat each Remaining
    ) -> ThrowingZipAsyncSequence<
        (Self, Second, repeat each Remaining),
        (AsyncIterator, Second.AsyncIterator, repeat (each Remaining).AsyncIterator),
        (Element, Second.Element, repeat (each Remaining).Element)
    > {
        makeThrowingZip(self, second, repeat each remaining)
    }

    /// Creates an asynchronous sequence that zips this async sequence with any number of
    /// others, and always needs `try`.
    ///
    /// It behaves like `zip(_:_:)`, but never picks an overload that needs no `try`. Use it
    /// below macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2, where `zip` with two or
    /// three sequences lets the first sequence alone decide whether `try` is needed: if the
    /// first sequence never throws and a later one does, `collect()`, `first()` and the other
    /// `rethrows` methods compile without `try` there, and the error is lost.
    ///
    /// ```swift
    /// let numbers = [1, 2].async
    /// let words = AsyncThrowingStream<String, Error> { continuation in
    ///     continuation.yield("one")
    ///     continuation.finish(throwing: TestError())
    /// }
    ///
    /// do {
    ///     for try await (number, word) in numbers.tryZip(words) {
    ///         print(number, word)
    ///     }
    /// } catch {
    ///     print("Error!")
    /// }
    ///
    /// // Prints:
    /// // 1 one
    /// // Error!
    /// ```
    /// - Parameters:
    ///   - second: The second async sequence to zip.
    ///   - remaining: Any further async sequences to zip.
    /// - Returns: An async sequence that zips the elements of this and the other async sequences.
    public func tryZip<Second: AsyncSequence, each Remaining: AsyncSequence>(
        _ second: Second,
        _ remaining: repeat each Remaining
    ) -> ThrowingZipAsyncSequence<
        (Self, Second, repeat each Remaining),
        (AsyncIterator, Second.AsyncIterator, repeat (each Remaining).AsyncIterator),
        (Element, Second.Element, repeat (each Remaining).Element)
    > {
        makeThrowingZip(self, second, repeat each remaining)
    }
}
