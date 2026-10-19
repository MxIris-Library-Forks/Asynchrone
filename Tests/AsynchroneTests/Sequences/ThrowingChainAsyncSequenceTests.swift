import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ThrowingChainAsyncSequenceTests {
        @Test func `Chaining two sequences`() async throws {
            let values = try await [1, 2, 3].async
                .tryChain(with: [4, 5, 6].async)
                .collect()

            #expect(values == [1, 2, 3, 4, 5, 6])
        }

        @Test func `tryChain throws an error from the second sequence`() async {
            let numbers = [1, 2].async
            let moreNumbers = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(3)
                continuation.finish(throwing: TestError())
            }

            await #expect(throws: TestError.self) {
                _ = try await numbers.tryChain(with: moreNumbers).collect()
            }
        }

        @Test func `Second sequence is not started before the first one finishes`() async throws {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            first.send(1)

            var iterator = first
                .tryChain(with: second)
                .makeAsyncIterator()

            let firstValue = try await iterator.next()
            #expect(firstValue == 1)
            #expect(second.madeIteratorCount == 0)
        }

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `Chaining a sequence that can throw`() async throws {
            let moreNumbers = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(3)
                continuation.finish()
            }

            var values: [Int] = []
            for try await value in [1, 2].async.chain(with: moreNumbers) {
                values.append(value)
            }

            #expect(values == [1, 2, 3])
        }
    }
}
