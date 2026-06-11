import XCTest
@testable import Asynchrone

final class AnyThrowingAsyncSequenceableTests: XCTestCase {
    func testErasingFail() async throws {
        await XCTAsyncAssertThrow {
            _ = try await Fail<Int, TestError>(error: .init())
                .eraseToAnyThrowingAsyncSequenceable()
                .collect()
        }
    }

    func testErasingNonThrowingSequence() async throws {
        let values = try await Just(1)
            .eraseToAnyThrowingAsyncSequenceable()
            .collect()
        XCTAssertEqual(values, [1])
    }

    func testOptionalInitializerWithValue() async throws {
        let optionalJust: Just<Int>? = Just(1)
        let sequence = try XCTUnwrap(AnyThrowingAsyncSequenceable<Int>(optionalJust))

        let values = try await sequence.collect()
        XCTAssertEqual(values, [1])
    }

    func testOptionalInitializerWithNil() {
        let nilSequence: Just<Int>? = nil
        XCTAssertNil(AnyThrowingAsyncSequenceable<Int>(nilSequence))
    }
}
