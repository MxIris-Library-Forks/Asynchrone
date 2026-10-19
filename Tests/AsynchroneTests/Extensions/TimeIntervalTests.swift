import Foundation
import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct TimeIntervalTests {
        @Test(arguments: [
            (1.0, 1_000_000_000.0),
            (1.5, 1_500_000_000.0),
            (-1.0, -1_000_000_000.0),
        ])
        func `Whole and negative seconds convert to nanoseconds`(seconds: TimeInterval, nanoseconds: TimeInterval) {
            #expect(seconds.asNanoseconds == nanoseconds)
        }

        @Test(arguments: [
            (0.1, 100_000_000.0),
            (0.05, 50_000_000.0),
        ])
        func `Fractional seconds convert to nanoseconds`(seconds: TimeInterval, nanoseconds: TimeInterval) {
            #expect(abs(seconds.asNanoseconds - nanoseconds) <= 1)
        }
    }
}
