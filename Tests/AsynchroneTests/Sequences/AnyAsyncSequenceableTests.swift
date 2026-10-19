import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct AnyAsyncSequenceableTests {
        @Test func `Erasing Just`() async {
            let values = await Just(1)
                .eraseToAnyAsyncSequenceable()
                .collect()

            #expect(values == [1])
        }

        @Test func `Optional initializer with a value`() async throws {
            let optionalJust: Just<Int>? = Just(1)
            let sequence = try #require(AnyAsyncSequenceable<Int>(optionalJust))

            let values = await sequence.collect()
            #expect(values == [1])
        }

        @Test func `Optional initializer with nil`() {
            let nilSequence: Just<Int>? = nil
            #expect(AnyAsyncSequenceable<Int>(nilSequence) == nil)
        }

        @Test func `Erased throwing sequence finishes on error`() async {
            // Errors cannot be surfaced through a non-throwing erasure;
            // the sequence finishes instead.
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(1)
                continuation.finish(throwing: TestError())
            }

            let values = await stream
                .eraseToAnyAsyncSequenceable()
                .collect()

            #expect(values == [1])
        }

        @Test func `Erasing a sequence of optional elements still finishes`() async {
            var iterator = [1, nil, 3].async
                .eraseToAnyAsyncSequenceable()
                .makeAsyncIterator()

            // Bounded, so that a sequence that never finishes fails instead of looping forever.
            var elements: [Int?] = []
            for _ in 0..<10 {
                guard let element = await iterator.next() else { break }
                elements.append(element)
            }

            #expect(elements == [1, nil, 3])
        }
    }
}
