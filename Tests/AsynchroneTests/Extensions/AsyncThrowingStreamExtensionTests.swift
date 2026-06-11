import XCTest
@testable import Asynchrone

final class AsyncThrowingStreamExtensionTests: XCTestCase {
    func testAsyncBuildInitializer() async throws {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(0)
            try? await Task.sleep(seconds: 0.1)
            continuation.yield(1)
            continuation.finish()
        }

        let values = try await stream.collect()
        XCTAssertEqual(values, [0, 1])
    }

    func testAsyncBuildInitializerRethrowsError() async {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(0)
            continuation.finish(throwing: TestError())
        }

        await XCTAsyncAssertThrow {
            _ = try await stream.collect()
        }
    }

    func testBuildTaskIsCancelledOnTermination() async throws {
        let buildTaskCancelled = expectation(description: "Build task cancelled")

        // The stream must be released for the termination handler to fire,
        // so keep it inside a narrower scope.
        do {
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(0)
                do {
                    try await Task.sleep(seconds: 10)
                } catch {
                    buildTaskCancelled.fulfill()
                }
            }

            let firstValue = try await stream.first()
            XCTAssertEqual(firstValue, 0)
        }

        await fulfillment(of: [buildTaskCancelled], timeout: 5)
    }

    func testFinishWithValue() async throws {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(0)
            continuation.finish(with: 1)
        }

        let values = try await stream.collect()
        XCTAssertEqual(values, [0, 1])
    }
}
