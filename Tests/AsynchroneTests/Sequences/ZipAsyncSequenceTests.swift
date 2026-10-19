import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ZipAsyncSequenceTests {
        private let sequenceA = [1, 2].async.eraseToAnyAsyncSequenceable()
        private let sequenceB = [5, 6, 7].async.eraseToAnyAsyncSequenceable()

        @Test func `Zipping two sequences`() async {
            let values = await self.sequenceA
                .zip(self.sequenceB)
                .collect()
                .map { [$0.0, $0.1] }

            #expect(values == [[1, 5], [2, 6]])
        }

        @Test func `Zip finishes when the first sequence ends`() async throws {
            let sequenceA = [1].async

            // This stream never finishes.
            let streamB = AsyncStream<Int> { continuation in
                continuation.yield(5)
            }

            let values = try await result(within: 5) {
                await sequenceA.zip(streamB).collect()
            }

            #expect(values?.count == 1)
        }

        @Test func `Iterating creates exactly one iterator of each sequence`() async {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            for probe in [first, second] {
                probe.send(1)
                probe.finish()
            }

            let values = await first
                .zip(second)
                .collect()

            #expect(values.count == 1)
            #expect([first, second].map(\.madeIteratorCount) == [1, 1])
        }

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `An error from the second sequence is thrown`() async throws {
            let numbers = [1, 2].async
            let words = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("a")
                continuation.finish(throwing: TestError())
            }

            // The first sequence never throws. While it alone decided whether the zipped
            // sequence throws, `collect()` needed no `try` and never returned.
            let outcome = try await result(within: 5) {
                do {
                    _ = try await numbers.zip(words).collect()
                    return "finished"
                } catch is TestError {
                    return "threw"
                }
            }

            #expect(outcome == "threw")
        }

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `Zipping sequences that never throw needs no try`() async {
            // Compiles only while this picks the overload for sequences that never throw.
            let values = await [1, 2].async
                .zip([5, 6, 7].async)
                .collect()
                .map { [$0.0, $0.1] }

            #expect(values == [[1, 5], [2, 6]])
        }
    }
}
