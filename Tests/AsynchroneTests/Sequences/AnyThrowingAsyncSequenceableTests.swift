import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct AnyThrowingAsyncSequenceableTests {
        @Test func `Erasing Fail`() async {
            await #expect(throws: TestError.self) {
                _ = try await Fail<Int, TestError>(error: .init())
                    .eraseToAnyThrowingAsyncSequenceable()
                    .collect()
            }
        }

        @Test func `Erasing a non-throwing sequence`() async throws {
            let values = try await Just(1)
                .eraseToAnyThrowingAsyncSequenceable()
                .collect()

            #expect(values == [1])
        }

        @Test func `Optional initializer with a value`() async throws {
            let optionalJust: Just<Int>? = Just(1)
            let sequence = try #require(AnyThrowingAsyncSequenceable<Int>(optionalJust))

            let values = try await sequence.collect()
            #expect(values == [1])
        }

        @Test func `Optional initializer with nil`() {
            let nilSequence: Just<Int>? = nil
            #expect(AnyThrowingAsyncSequenceable<Int>(nilSequence) == nil)
        }

        @Test func `Erasing a sequence of optional elements still finishes`() async throws {
            var iterator = [1, nil, 3].async
                .eraseToAnyThrowingAsyncSequenceable()
                .makeAsyncIterator()

            // Bounded, so that a sequence that never finishes fails instead of looping forever.
            var elements: [Int?] = []
            for _ in 0..<10 {
                guard let element = try await iterator.next() else { break }
                elements.append(element)
            }

            #expect(elements == [1, nil, 3])
        }
    }
}
