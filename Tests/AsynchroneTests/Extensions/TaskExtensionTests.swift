import XCTest
@testable import Asynchrone

final class TaskExtensionTests: XCTestCase {
    func testSleepSeconds() async throws {
        let start = Date()
        try await Task.sleep(seconds: 0.5)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.5)
    }

    func testSleepFractionalSeconds() async throws {
        let start = Date()
        try await Task.sleep(seconds: 0.1)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.1)
    }

    func testSleepNegativeSecondsDoesNotCrash() async throws {
        let start = Date()
        try await Task.sleep(seconds: -5)
        let elapsed = Date().timeIntervalSince(start)

        // A negative duration is treated as zero and returns promptly.
        XCTAssertLessThan(elapsed, 1)
    }
}
