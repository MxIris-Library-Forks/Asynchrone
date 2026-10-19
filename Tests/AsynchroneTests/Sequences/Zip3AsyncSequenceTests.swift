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

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `An error from a later sequence is thrown`() async throws {
            let numbers = [1, 2].async
            let letters = ["a", "b"].async
            let words = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("one")
                continuation.finish(throwing: TestError())
            }

            // The first sequence never throws. While it alone decided whether the zipped
            // sequence throws, `collect()` needed no `try` and never returned.
            let outcome = try await result(within: 5) {
                do {
                    _ = try await numbers.zip(letters, words).collect()
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
                .zip([5, 6, 7].async, [8, 9].async)
                .collect()
                .map { "\($0.0)-\($0.1)-\($0.2)" }

            #expect(values == ["1-5-8", "2-6-9"])
        }
    }
}
