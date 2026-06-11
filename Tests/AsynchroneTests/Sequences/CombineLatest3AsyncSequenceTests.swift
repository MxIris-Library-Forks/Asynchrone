import XCTest
@testable import Asynchrone

final class CombineLatest3AsyncSequenceTests: XCTestCase {
    func testCombiningStaggeredSequences() async {
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

        XCTAssertEqual(values, ["1-5-10", "2-5-10"])
    }

    func testFinishesWhenOneSequenceIsEmpty() async {
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

        XCTAssertTrue(values.isEmpty)
    }

    func testErrorIsRethrown() async {
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
        await XCTAsyncAssertThrow {
            _ = try await sequence.collect()
        }
    }
}
