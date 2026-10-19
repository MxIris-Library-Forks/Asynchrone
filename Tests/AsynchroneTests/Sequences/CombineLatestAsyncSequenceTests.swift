import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct CombineLatestAsyncSequenceTests {
        @Test func `Combining staggered sequences`() async {
            let streamA = AsyncStream<Int> { continuation in
                continuation.yield(1)
                try? await Task.sleep(seconds: 0.5)
                continuation.yield(2)
                continuation.finish()
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.2)
                continuation.yield(5)
                try? await Task.sleep(seconds: 0.2)
                continuation.yield(6)
                continuation.finish()
            }

            let values = await streamA
                .combineLatest(streamB)
                .collect()
                .map { "\($0.0)-\($0.1)" }

            #expect(values == ["1-5", "1-6", "2-6"])
        }

        @Test func `Finishes when one sequence is empty`() async {
            let emptyStream = AsyncStream<Int> { continuation in
                continuation.finish()
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.1)
                continuation.yield(5)
                continuation.finish()
            }

            let values = await emptyStream
                .combineLatest(streamB)
                .collect()

            #expect(values.isEmpty)
        }

        @Test func `Continues with the last value after one sequence finishes`() async {
            let streamA = AsyncStream<Int> { continuation in
                continuation.finish(with: 1)
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.2)
                continuation.yield(5)
                try? await Task.sleep(seconds: 0.2)
                continuation.yield(6)
                continuation.finish()
            }

            let values = await streamA
                .combineLatest(streamB)
                .collect()
                .map { "\($0.0)-\($0.1)" }

            #expect(values == ["1-5", "1-6"])
        }

        @Test func `Error is rethrown`() async {
            // NOTE: the throwing sequence must be in the FIRST position. With a
            // non-throwing first sequence the specialized `next()` witness is
            // treated as non-throwing in generic rethrows contexts and the error
            // is lost (see the note in Common/ErrorMechanism.swift).
            let streamA = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(1)
                try? await Task.sleep(seconds: 0.2)
                continuation.finish(throwing: TestError())
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.1)
                continuation.yield(5)
                try? await Task.sleep(seconds: 0.5)
                continuation.finish()
            }

            let sequence = streamA.combineLatest(streamB)
            await #expect(throws: TestError.self) {
                _ = try await sequence.collect()
            }
        }

        @Test func `Stopping early leaves no task waiting on the upstreams`() async {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            first.send(1)
            second.send(2)

            let marker = await TaskTracking.run {
                _ = await first.combineLatest(second).first()
            }

            #expect(await eventually(timeout: 1) { marker.object == nil })

            first.finish()
            second.finish()
        }

        @Test func `Rounds do not pile up tasks while one side stays silent`() async {
            let fast = ProbeAsyncSequence<Int>()
            let silent = ProbeAsyncSequence<Int>()
            silent.send(0)

            var iterator = fast
                .combineLatest(silent)
                .makeAsyncIterator()

            var markers: [WeakReference<TaskTracking.Marker>] = []
            for element in 0..<50 {
                fast.send(element)
                markers.append(await TaskTracking.run { _ = await iterator.next() })
            }

            // Only the task that is still waiting on the silent side may outlive its round.
            await eventually(timeout: 1) { markers.filter { $0.object != nil }.count <= 1 }
            let roundsWithLiveTasks = markers.filter { $0.object != nil }.count
            #expect(roundsWithLiveTasks <= 1)

            fast.finish()
            silent.finish()
        }
    }
}
