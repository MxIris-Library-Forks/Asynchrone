import Foundation
import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct TaskExtensionTests {
        @Test(arguments: [0.5, 0.1])
        func `Sleep lasts at least the given number of seconds`(seconds: TimeInterval) async throws {
            let start = Date()
            try await Task.sleep(seconds: seconds)

            #expect(Date().timeIntervalSince(start) >= seconds)
        }

        @Test func `Sleeping for negative seconds does not crash`() async throws {
            let start = Date()
            try await Task.sleep(seconds: -5)

            // A negative duration is treated as zero and returns promptly.
            #expect(Date().timeIntervalSince(start) < 1)
        }

        @Test func `Sleeping for an infinite duration does not crash`() async {
            await #expect(processExitsWith: .success) {
                let sleeper = Task {
                    try await Task.sleep(seconds: .infinity)
                }

                try? await Task.sleep(for: .milliseconds(50))
                sleeper.cancel()
                _ = await sleeper.result
            }
        }
    }
}
