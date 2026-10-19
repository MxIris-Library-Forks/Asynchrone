import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct AsyncThrowingStreamExtensionTests {
        @Test func `Async build initializer`() async throws {
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(0)
                try? await Task.sleep(seconds: 0.1)
                continuation.yield(1)
                continuation.finish()
            }

            let values = try await stream.collect()
            #expect(values == [0, 1])
        }

        @Test func `Async build initializer rethrows error`() async {
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(0)
                continuation.finish(throwing: TestError())
            }

            await #expect(throws: TestError.self) {
                _ = try await stream.collect()
            }
        }

        @Test func `Build task is cancelled on termination`() async throws {
            let buildTaskCancelled = Flag()

            // The stream must be released for the termination handler to fire,
            // so keep it inside a narrower scope.
            do {
                let stream = AsyncThrowingStream<Int, Error> { continuation in
                    continuation.yield(0)
                    do {
                        try await Task.sleep(seconds: 10)
                    } catch {
                        buildTaskCancelled.set()
                    }
                }

                let firstValue = try await stream.first()
                #expect(firstValue == 0)
            }

            #expect(await eventually { buildTaskCancelled.isSet })
        }

        @Test func `Finish with value`() async throws {
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(0)
                continuation.finish(with: 1)
            }

            let values = try await stream.collect()
            #expect(values == [0, 1])
        }
    }
}
