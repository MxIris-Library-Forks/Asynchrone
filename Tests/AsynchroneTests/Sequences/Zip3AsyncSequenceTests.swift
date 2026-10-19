import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct Zip3AsyncSequenceTests {
        @Test func `Zipping three sequences`() async {
            let sequenceA = [1, 2].async
            let sequenceB = [5, 6, 7].async
            let sequenceC = [8, 9].async

            let values = await sequenceA
                .zip(sequenceB, sequenceC)
                .collect()
                .map { "\($0.0)-\($0.1)-\($0.2)" }

            #expect(values == ["1-5-8", "2-6-9"])
        }

        @Test func `Zip finishes when the first sequence ends`() async throws {
            let sequenceA = [1].async

            // These streams never finish.
            let streamB = AsyncStream<Int> { continuation in
                continuation.yield(5)
            }
            let streamC = AsyncStream<Int> { continuation in
                continuation.yield(8)
            }

            let values = try await result(within: 5) {
                await sequenceA.zip(streamB, streamC).collect()
            }

            #expect(values?.count == 1)
        }

        @Test func `Iterating creates exactly one iterator of each sequence`() async {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            let third = ProbeAsyncSequence<Int>()
            for probe in [first, second, third] {
                probe.send(1)
                probe.finish()
            }

            let values = await first
                .zip(second, third)
                .collect()

            #expect(values.count == 1)
            #expect([first, second, third].map(\.madeIteratorCount) == [1, 1, 1])
        }
    }
}
