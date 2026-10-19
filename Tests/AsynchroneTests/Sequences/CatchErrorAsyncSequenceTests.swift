import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct CatchErrorTests {
        @Test func `Error caught`() async {
            let replacement = 0

            let values = await Fail<Int, TestError>(
                error: TestError()
            )
            .catch { _ in
                Just(replacement)
            }
            .collect()

            #expect(values == [replacement])
        }

        @Test func `Iterating creates exactly one upstream iterator`() async {
            let upstream = ProbeAsyncSequence<Int>()
            upstream.send(1)
            upstream.finish()

            let values = await upstream
                .catch { _ in Just(0) }
                .collect()

            #expect(values == [1])
            #expect(upstream.madeIteratorCount == 1)
        }

        @Test func `Catching errors of merged passthrough sequences does not crash`() async {
            await #expect(processExitsWith: .success) {
                let first = ThrowingPassthroughAsyncSequence<Int>()
                let second = ThrowingPassthroughAsyncSequence<Int>()

                let consumer = Task {
                    await first
                        .merge(with: second)
                        .catch { _ in Just(-1) }
                        .collect()
                }

                try? await Task.sleep(for: .milliseconds(100))
                first.yield(1)
                first.finish()
                second.finish()
                _ = await consumer.value
            }
        }
    }
}
