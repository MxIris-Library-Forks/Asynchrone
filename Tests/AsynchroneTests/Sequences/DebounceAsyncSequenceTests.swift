import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct DebounceAsyncSequenceTests {
        @Test func debounce() async {
            let stream = AsyncStream<Int> { continuation in
                continuation.yield(0)
                try? await Task.sleep(seconds: 0.4)
                continuation.yield(1)
                continuation.yield(2)
                try? await Task.sleep(seconds: 0.4)
                continuation.yield(3)
                try? await Task.sleep(seconds: 0.4)
                continuation.finish()
            }

            let values = await stream
                .debounce(for: 0.1)
                .collect()

            #expect(values == [0, 2, 3])
        }

        @Test func `Debounce with no values`() async {
            let values = await AsyncStream<Int> {
                $0.finish()
            }
            .debounce(for: 0.3)
            .collect()

            #expect(values.isEmpty)
        }

        @Test func `Sequence that finishes at once emits nothing`() async {
            let values = await Just(0)
                .debounce(for: 0.3)
                .collect()

            #expect(values.isEmpty)
        }

        @Test func `Sub-second debounce`() async {
            let stream = AsyncStream<Int> { continuation in
                continuation.yield(0)
                continuation.yield(1)
                continuation.yield(2)
                try? await Task.sleep(seconds: 0.3)
                continuation.yield(3)
                try? await Task.sleep(seconds: 0.3)
                continuation.finish()
            }

            let values = await stream
                .debounce(for: 0.1)
                .collect()

            #expect(values == [2, 3])
        }

        @Test func `Negative due time does not crash`() async {
            let stream = AsyncStream<Int> { continuation in
                continuation.yield(0)
                continuation.yield(1)
                continuation.finish()
            }

            _ = await stream
                .debounce(for: -1)
                .collect()
        }

        @Test func `Infinite due time does not crash`() async {
            await #expect(processExitsWith: .success) {
                _ = await Just(1)
                    .debounce(for: .infinity)
                    .collect()
            }
        }

        @Test func `Stopping early leaves no task waiting on the upstream`() async {
            let upstream = ProbeAsyncSequence<Int>()
            upstream.send(1)

            let marker = await TaskTracking.run {
                _ = await upstream.debounce(for: 0.05).first()
            }

            #expect(await eventually(timeout: 1) { marker.object == nil })

            upstream.finish()
        }

        @Test func `Sleeps do not outlive the iteration`() async {
            let upstream = ProbeAsyncSequence<Int>()
            for element in 0..<100 {
                upstream.send(element)
            }
            upstream.finish()

            // Every element arrives well within the due time, so each one ends a round
            // in which a ten-second sleep lost the race.
            let marker = await TaskTracking.run {
                _ = await upstream.debounce(for: 10).collect()
            }

            #expect(await eventually(timeout: 1) { marker.object == nil })
        }

        @Test func `Cancelling the consumer ends the iteration even if the upstream ignores cancellation`() async throws {
            let upstream = ProbeAsyncSequence<Int>(respondsToCancellation: false)
            let consumer = Task {
                await upstream.debounce(for: 0.05).first()
            }

            try await Task.sleep(for: .milliseconds(100))
            consumer.cancel()
            let consumerResult = try await result(within: 0.5) { await consumer.value }

            #expect(consumerResult != nil)

            // Let the upstream call that ignored cancellation return, so that nothing keeps running.
            upstream.finish()
        }
    }
}
