import Foundation
import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct DelayAsyncSequenceTests {
        private let sequence = [0, 1, 2].async.eraseToAnyAsyncSequenceable()

        @Test func delay() async throws {
            var values: [TimestampedValue<Int>] = []
            for await value in self.sequence.delay(for: 0.5) {
                values.append(.init(value: value))
            }

            try #require(values.count == 3)
            #expect(values[1].timestamp.timeIntervalSince(values[0].timestamp) >= 0.5)
            #expect(values[2].timestamp.timeIntervalSince(values[1].timestamp) >= 0.5)
            #expect(values.map(\.value) == [0, 1, 2])
        }

        @Test func `Cancellation stops emission`() async {
            let stream = AsyncStream<Int> { continuation in
                continuation.yield(0)
                continuation.finish()
            }

            let task = Task { await stream.delay(for: 2).collect() }

            try? await Task.sleep(seconds: 0.2)
            task.cancel()

            let values = await task.value
            #expect(values.isEmpty)
        }
    }
}

// MARK: TimestampedValue

fileprivate struct TimestampedValue<Value> {
    var value: Value
    var timestamp = Date()
}
