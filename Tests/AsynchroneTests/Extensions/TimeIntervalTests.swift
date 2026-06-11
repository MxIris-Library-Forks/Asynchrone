import XCTest
@testable import Asynchrone

final class TimeIntervalTests: XCTestCase {
    func testAsNanoseconds() {
        XCTAssertEqual(1.asNanoseconds, 1_000_000_000)
        XCTAssertEqual(1.5.asNanoseconds, 1_500_000_000)
    }

    func testFractionalAsNanoseconds() {
        XCTAssertEqual(0.1.asNanoseconds, 100_000_000, accuracy: 1)
        XCTAssertEqual(0.05.asNanoseconds, 50_000_000, accuracy: 1)
    }

    func testNegativeAsNanoseconds() {
        XCTAssertEqual((-1.0).asNanoseconds, -1_000_000_000)
    }
}
