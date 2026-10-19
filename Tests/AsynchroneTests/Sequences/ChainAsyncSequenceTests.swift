import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ChainAsyncSequenceTests {
        private let sequenceA = [1, 2, 3].async
        private let sequenceB = [4, 5, 6].async
        private let sequenceC = [7, 8, 9].async

        @Test func `Chaining two sequences`() async {
            let values = await self.sequenceA
                .chain(with: self.sequenceB)
                .collect()

            #expect(values == [1, 2, 3, 4, 5, 6])
        }

        @Test func `Chaining three sequences`() async {
            let values = await self.sequenceA
                .chain(with: self.sequenceB)
                .chain(with: self.sequenceC)
                .collect()

            #expect(values == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        }

        @Test func `Iterating creates exactly one iterator of each sequence`() async {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            first.send(1)
            first.finish()
            second.send(2)
            second.finish()

            let values = await first
                .chain(with: second)
                .collect()

            #expect(values == [1, 2])
            #expect(first.madeIteratorCount == 1)
            #expect(second.madeIteratorCount == 1)
        }

        @Test func `Second sequence is not started before the first one finishes`() async {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            first.send(1)

            var iterator = first
                .chain(with: second)
                .makeAsyncIterator()

            let firstValue = await iterator.next()
            #expect(firstValue == 1)
            #expect(second.madeIteratorCount == 0)
        }

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `An error from the second sequence is thrown`() async throws {
            let numbers = [1, 2].async
            let moreNumbers = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(3)
                continuation.finish(throwing: TestError())
            }

            // The first sequence never throws. While it alone decided whether the chained
            // sequence throws, `collect()` needed no `try` and never returned.
            let outcome = try await result(within: 5) {
                do {
                    _ = try await numbers.chain(with: moreNumbers).collect()
                    return "finished"
                } catch is TestError {
                    return "threw"
                }
            }

            #expect(outcome == "threw")
        }

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `Chaining sequences that never throw needs no try`() async {
            // Compiles only while this picks the overload for sequences that never throw.
            let values = await self.sequenceA
                .chain(with: self.sequenceB)
                .collect()

            #expect(values == [1, 2, 3, 4, 5, 6])
        }
    }
}
