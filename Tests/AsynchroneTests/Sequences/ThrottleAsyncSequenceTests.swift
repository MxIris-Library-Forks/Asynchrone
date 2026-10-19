import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ThrottleAsyncSequenceTests {
        private let sequence = AsyncStream<Int> { continuation in
            continuation.yield(0)
            try? await Task.sleep(nanoseconds: 100_000_000)
            continuation.yield(1)
            try? await Task.sleep(nanoseconds: 100_000_000)
            continuation.yield(2)
            continuation.yield(3)
            continuation.yield(4)
            continuation.yield(5)
            continuation.finish()
        }

        @Test func throttle() async {
            let values = await self.sequence
                .throttle(for: 0.05, latest: false)
                .collect()

            #expect(values == [0, 1, 2, 3])
        }

        @Test func `Throttle latest`() async {
            let values = await self.sequence
                .throttle(for: 0.05, latest: true)
                .collect()

            #expect(values == [0, 1, 2, 5])
        }

        @Test func `Throttle with no values`() async {
            let values = await AsyncStream<Int> {
                $0.finish()
            }
            .throttle(for: 0.05, latest: true)
            .collect()

            #expect(values.isEmpty)
        }

        @Test func `Throttle with one value`() async {
            let values = await Just(0)
                .throttle(for: 0.05, latest: true)
                .collect()

            #expect(values == [0])
        }

        @Test func `Latest element is emitted once the interval elapses`() async throws {
            let upstream = PassthroughAsyncSequence<Int>()

            // The second element arrives within the interval of the first, and nothing follows it.
            upstream.yield(0)
            upstream.yield(1)

            let values = try await result(within: 1) {
                await upstream
                    .throttle(for: 0.05, latest: true)
                    .collect(2)
            }

            #expect(values == [0, 1])
        }

        @Test func `First element after a quiet period is not dropped`() async throws {
            let upstream = PassthroughAsyncSequence<Int>()
            let consumer = Task {
                await upstream
                    .throttle(for: 0.05, latest: false)
                    .collect()
            }

            upstream.yield(0)
            upstream.yield(1)
            try await Task.sleep(for: .milliseconds(300))
            upstream.yield(2)
            upstream.finish()

            let values = try await result(within: 5) { await consumer.value }
            #expect(values == [0, 1, 2])
        }
    }
}
