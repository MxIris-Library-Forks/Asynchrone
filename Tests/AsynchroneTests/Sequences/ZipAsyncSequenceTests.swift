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
    }
}
