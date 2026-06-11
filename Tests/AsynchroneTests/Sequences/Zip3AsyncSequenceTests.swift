import XCTest
@testable import Asynchrone

final class Zip3AsyncSequenceTests: XCTestCase {
    func testZippingThreeSequences() async {
        let sequenceA = [1, 2].async
        let sequenceB = [5, 6, 7].async
        let sequenceC = [8, 9].async

        let values = await sequenceA
            .zip(sequenceB, sequenceC)
            .collect()
            .map { "\($0.0)-\($0.1)-\($0.2)" }

        XCTAssertEqual(values, ["1-5-8", "2-6-9"])
    }

    func testZipFinishesWhenFirstSequenceEnds() async {
        let sequenceA = [1].async

        // These streams never finish.
        let streamB = AsyncStream<Int> { continuation in
            continuation.yield(5)
        }
        let streamC = AsyncStream<Int> { continuation in
            continuation.yield(8)
        }

        let zipFinished = expectation(description: "Zip finished")
        let task = Task {
            let values = await sequenceA.zip(streamB, streamC).collect()
            XCTAssertEqual(values.count, 1)
            zipFinished.fulfill()
        }

        await fulfillment(of: [zipFinished], timeout: 5)
        task.cancel()
    }
}
