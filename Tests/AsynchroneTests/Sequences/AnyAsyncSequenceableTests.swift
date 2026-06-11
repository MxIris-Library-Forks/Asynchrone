import XCTest
@testable import Asynchrone

final class AnyAsyncSequenceableTests: XCTestCase {
    func testErasingJust() async throws {
        let values = await Just(1)
            .eraseToAnyAsyncSequenceable()
            .collect()
        XCTAssertEqual(values, [1])
    }

    func testOptionalInitializerWithValue() async throws {
        let optionalJust: Just<Int>? = Just(1)
        let sequence = try XCTUnwrap(AnyAsyncSequenceable<Int>(optionalJust))

        let values = await sequence.collect()
        XCTAssertEqual(values, [1])
    }

    func testOptionalInitializerWithNil() {
        let nilSequence: Just<Int>? = nil
        XCTAssertNil(AnyAsyncSequenceable<Int>(nilSequence))
    }

    func testErasedThrowingSequenceFinishesOnError() async {
        // Errors cannot be surfaced through a non-throwing erasure;
        // the sequence finishes instead.
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: TestError())
        }

        let values = await stream
            .eraseToAnyAsyncSequenceable()
            .collect()

        XCTAssertEqual(values, [1])
    }
}
