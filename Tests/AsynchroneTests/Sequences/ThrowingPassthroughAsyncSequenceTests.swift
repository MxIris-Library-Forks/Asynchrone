import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ThrowingPassthroughAsyncSequenceTests {
        private let sequence = ThrowingPassthroughAsyncSequence<Int>()

        @Test func `Sequence emits every element`() async throws {
            self.sequence.yield(0)
            self.sequence.yield(1)
            self.sequence.finish(with: 2)

            let values = try await self.sequence.collect()
            #expect(values == [0, 1, 2])
        }

        @Test func `Sequence throws`() async {
            self.sequence.finish(throwing: TestError())

            await #expect(throws: TestError.self) {
                try await self.sequence.collect()
            }
        }
    }
}
