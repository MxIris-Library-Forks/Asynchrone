import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct AsyncStreamExtensionTests {
        @Test func `Async build initializer`() async {
            let stream = AsyncStream<Int> { continuation in
                continuation.yield(0)
                try? await Task.sleep(seconds: 0.1)
                continuation.yield(1)
                continuation.finish()
            }

            let values = await stream.collect()
            #expect(values == [0, 1])
        }

        @Test func `Build task is cancelled on termination`() async {
            let buildTaskCancelled = Flag()

            // The stream must be released for the termination handler to fire,
            // so keep it inside a narrower scope.
            do {
                let stream = AsyncStream<Int> { continuation in
                    continuation.yield(0)
                    do {
                        try await Task.sleep(seconds: 10)
                    } catch {
                        buildTaskCancelled.set()
                    }
                }

                let firstValue = await stream.first()
                #expect(firstValue == 0)
            }

            #expect(await eventually { buildTaskCancelled.isSet })
        }

        @Test func `Finish with value`() async {
            let stream = AsyncStream<Int> { continuation in
                continuation.yield(0)
                continuation.finish(with: 1)
            }

            let values = await stream.collect()
            #expect(values == [0, 1])
        }
    }
}
