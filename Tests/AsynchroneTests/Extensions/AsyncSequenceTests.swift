import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct AsyncSequenceTests {
        private let sequence = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }

        // MARK: Assign

        @Test func assign() async {
            let target = AssignTarget()
            self.sequence.assign(to: \.value, on: target)
            #expect(await eventually { target.value == 3 })
        }

        // MARK: First

        @Test func first() async {
            let element = await self.sequence.first()
            #expect(element == 1)
        }

        // MARK: Last

        @Test func last() async {
            let element = await self.sequence.last()
            #expect(element == 3)
        }

        // MARK: Collect

        @Test func collect() async {
            let values = await self.sequence.collect()
            #expect(values == [1, 2, 3])
        }

        @Test func `Collect with limit`() async {
            let values = await self.sequence.collect(2)
            #expect(values == [1, 2])
        }

        @Test(arguments: [0, -1])
        func `Collecting zero or fewer elements returns at once`(numberOfElements: Int) async throws {
            let neverEmitting = PassthroughAsyncSequence<Int>()
            let values = try await result(within: 1) {
                await neverEmitting.collect(numberOfElements)
            }

            #expect(values == [])
        }

        // MARK: Sink

        @Test func sink() async {
            let store = Store<Int>()
            self.sequence.sink { await store.append($0) }

            await eventually { await store.values.count == 3 }
            let values = await store.values
            #expect(values == [1, 2, 3])
        }

        @Test func `Sink with finished completion`() async {
            let store = Store<Int>()
            await confirmation("Completion called with finished") { completionCalled in
                let task = self.sequence.sink(
                    receiveValue: { await store.append($0) },
                    receiveCompletion: { completion in
                        if case .finished = completion {
                            completionCalled()
                        }
                    }
                )
                await task.value
            }

            let values = await store.values
            #expect(values == [1, 2, 3])
        }

        @Test func `Sink with failed completion`() async {
            let sequence = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(1)
                continuation.yield(2)
                continuation.yield(3)
                continuation.finish(throwing: TestError())
            }

            let store = Store<Int>()
            await confirmation("Completion called with a failure") { completionCalled in
                let task = sequence.sink(
                    receiveValue: { await store.append($0) },
                    receiveCompletion: { completion in
                        if case .failure = completion {
                            completionCalled()
                        }
                    }
                )
                await task.value
            }

            let values = await store.values
            #expect(values == [1, 2, 3])
        }

        @Test func `Sink with cancellation`() async {
            let sequence = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(1)
            }

            let store = Store<Int>()
            await confirmation("Completion called with a cancellation error") { completionCalled in
                let task = sequence.sink(
                    receiveValue: { await store.append($0) },
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion, error is CancellationError {
                            completionCalled()
                        }
                    }
                )
                task.cancel()
                await task.value
            }

            let values = await store.values
            #expect(values == [1])
        }
    }
}

// MARK: Store

fileprivate actor Store<Element> {
    var values: [Element] = []

    fileprivate func append(_ newElement: Element) {
        self.values.append(newElement)
    }
}

// MARK: AssignTarget

fileprivate final class AssignTarget: @unchecked Sendable {
    var value: Int = 0
}
