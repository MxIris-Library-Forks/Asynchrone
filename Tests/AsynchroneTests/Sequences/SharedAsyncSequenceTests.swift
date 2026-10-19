import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct SharedAsyncSequenceTests {
        @Test func `Every consumer receives all values`() async throws {
            let sequence = PassthroughAsyncSequence<Int>().shared()

            let firstConsumer = Task {
                try await sequence.collect()
            }

            let secondConsumer = Task.detached {
                try await sequence.collect()
            }

            Task.detached {
                try? await Task.sleep(seconds: 0.5)
                sequence.yield(0)
                sequence.yield(1)
                sequence.yield(2)
                sequence.finish(with: 3)
            }

            let firstValues = try await result(within: 5) { try await firstConsumer.value }
            let secondValues = try await result(within: 5) { try await secondConsumer.value }
            #expect(firstValues == [0, 1, 2, 3])
            #expect(secondValues == [0, 1, 2, 3])
        }

        @Test func `Accessing the base CurrentElementAsyncSequence`() async throws {
            let valueA = 0
            let valueB = 1
            let valueC = 2

            let sequence = CurrentElementAsyncSequence(valueA).shared()

            // Yield new value
            await sequence.yield(valueB)
            await sequence.finish(with: valueC)

            let values = try await sequence.collect()
            let currentValue = await sequence.element()
            #expect(values == [0, 1, 2])
            #expect(currentValue == valueC)
        }

        @Test func `Accessing the base PassthroughAsyncSequence`() async throws {
            let valueA = 0
            let valueB = 1

            let sequence = PassthroughAsyncSequence<Int>().shared()

            // Yield new value
            sequence.yield(valueA)
            sequence.finish(with: valueB)

            let values = try await sequence.collect()
            #expect(values == [0, 1])
        }

        @Test func `Dropping the sequence cancels the subscription to the base`() async throws {
            let baseTerminated = Flag()

            var sequence: SharedAsyncSequence<AsyncStream<Int>>? = AsyncStream<Int> { continuation in
                continuation.onTermination = { @Sendable _ in
                    baseTerminated.set()
                }
                continuation.yield(0)
                // Never finishes.
            }
            .shared()

            let firstValue = try await sequence?.first()
            #expect(firstValue == 0)

            // Dropping the last reference must deinit the manager, which cancels
            // the subscription task and terminates the base sequence. Before the
            // retain cycle fix the manager and its task leaked forever.
            sequence = nil
            #expect(await eventually { baseTerminated.isSet })
        }

        @Test func `Subscribing after the base finished completes at once`() async throws {
            let sequence = [1, 2].async.shared()
            let values = try await sequence.collect()
            #expect(values == [1, 2])

            let lateValues = try await result(within: 1) {
                try await sequence.collect()
            }

            #expect(lateValues == [])
        }

        @Test func `Dropping an iterator at once does not keep the base subscribed`() async throws {
            // Dropping the iterator races with registering its subscriber, which happens on
            // a background task. Repeat, so that the race goes the bad way at least once;
            // it does almost every time.
            var upstreams: [ProbeAsyncSequence<Int>] = []
            for _ in 0..<20 {
                let upstream = ProbeAsyncSequence<Int>()
                upstreams.append(upstream)
                _ = upstream.shared().makeAsyncIterator()
            }

            // Let the background registrations run before checking.
            try await Task.sleep(for: .milliseconds(200))

            await eventually(timeout: 2) { upstreams.allSatisfy { $0.suspendedNextCount == 0 } }
            let stillSubscribedCount = upstreams.filter { $0.suspendedNextCount > 0 }.count
            #expect(stillSubscribedCount == 0)
        }
    }
}
