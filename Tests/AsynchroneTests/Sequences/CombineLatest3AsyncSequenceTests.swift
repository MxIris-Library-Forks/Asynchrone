import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct CombineLatest3AsyncSequenceTests {
        @Test func `Combining staggered sequences`() async {
            let streamA = AsyncStream<Int> { continuation in
                continuation.yield(1)
                try? await Task.sleep(seconds: 0.6)
                continuation.yield(2)
                continuation.finish()
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.2)
                continuation.yield(5)
                continuation.finish()
            }

            let streamC = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.4)
                continuation.yield(10)
                continuation.finish()
            }

            let values = await streamA
                .combineLatest(streamB, streamC)
                .collect()
                .map { "\($0.0)-\($0.1)-\($0.2)" }

            #expect(values == ["1-5-10", "2-5-10"])
        }

        @Test func `Finishes when one sequence is empty`() async {
            let streamA = AsyncStream<Int> { continuation in
                continuation.yield(1)
                continuation.finish()
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.1)
                continuation.yield(5)
                continuation.finish()
            }

            let emptyStream = AsyncStream<Int> { continuation in
                continuation.finish()
            }

            let values = await streamA
                .combineLatest(streamB, emptyStream)
                .collect()

            #expect(values.isEmpty)
        }

        @Test func `Error is rethrown`() async {
            // NOTE: the throwing sequence must be in the FIRST position. With a
            // non-throwing first sequence the specialized `next()` witness is
            // treated as non-throwing in generic rethrows contexts and the error
            // is lost (see the note in Common/ErrorMechanism.swift).
            let streamA = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(1)
                try? await Task.sleep(seconds: 0.3)
                continuation.finish(throwing: TestError())
            }

            let streamB = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.1)
                continuation.yield(5)
                try? await Task.sleep(seconds: 0.5)
                continuation.finish()
            }

            let streamC = AsyncStream<Int> { continuation in
                try? await Task.sleep(seconds: 0.2)
                continuation.yield(10)
                try? await Task.sleep(seconds: 0.5)
                continuation.finish()
            }

            let sequence = streamA.combineLatest(streamB, streamC)
            await #expect(throws: TestError.self) {
                _ = try await sequence.collect()
            }
        }

        @Test func `Stopping early leaves no task waiting on the upstreams`() async {
            let first = ProbeAsyncSequence<Int>()
            let second = ProbeAsyncSequence<Int>()
            let third = ProbeAsyncSequence<Int>()
            first.send(1)
            second.send(2)
            third.send(3)

            let marker = await TaskTracking.run {
                _ = await first.combineLatest(second, third).first()
            }

            #expect(await eventually(timeout: 1) { marker.object == nil })

            first.finish()
            second.finish()
            third.finish()
        }
    }
}
