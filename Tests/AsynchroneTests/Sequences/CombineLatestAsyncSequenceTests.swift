import XCTest
@testable import Asynchrone

final class CombineLatestAsyncSequenceTests: XCTestCase {
    func testCombiningStaggeredSequences() async {
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

        XCTAssertEqual(values, ["1-5", "1-6", "2-6"])
    }

    func testFinishesWhenOneSequenceIsEmpty() async {
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

        XCTAssertTrue(values.isEmpty)
    }

    func testContinuesWithLastValueAfterOneSequenceFinishes() async {
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

        XCTAssertEqual(values, ["1-5", "1-6"])
    }

    func testErrorIsRethrown() async {
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
        await XCTAsyncAssertThrow {
            _ = try await sequence.collect()
        }
    }
}
