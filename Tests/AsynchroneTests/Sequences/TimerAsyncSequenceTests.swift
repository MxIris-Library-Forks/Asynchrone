import Foundation
import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct TimerAsyncSequenceTests {
        private let sequence = TimerAsyncSequence(interval: 0.5)

        @Test func `Timer emissions`() async throws {
            var values: [Date] = []
            let start = Date()
            var end = Date()

            for await value in self.sequence {
                values.append(value)

                if values.count == 3 {
                    end = Date()
                    self.sequence.cancel()
                }
            }

            try #require(values.count == 3)
            #expect(end.timeIntervalSince(start) >= 1.5)
            #expect(values[1].timeIntervalSince(values[0]) >= 0.5)
            #expect(values[2].timeIntervalSince(values[1]) >= 0.5)
        }

        @Test func `Cancelling before iteration finishes at once`() async {
            let sequence = TimerAsyncSequence(interval: 0.1)
            sequence.cancel()

            let values = await sequence.collect()
            #expect(values.isEmpty)
        }

        @Test func `Negative interval does not crash`() async {
            let sequence = TimerAsyncSequence(interval: -5)

            for await _ in sequence {
                sequence.cancel()
            }
        }

        @Test func `Second iteration does not start another timer`() async {
            let sequence = TimerAsyncSequence(interval: 0.1)

            var firstIterationValueCount = 0
            for await _ in sequence {
                firstIterationValueCount += 1

                if firstIterationValueCount == 2 {
                    sequence.cancel()
                }
            }

            // The timer task has finished; a new iteration must complete
            // immediately instead of spawning another timer task.
            let values = await sequence.collect()
            #expect(values.isEmpty)
        }
    }
}
