import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct PassthroughAsyncSequenceTests {
        private let sequence = PassthroughAsyncSequence<Int>()

        @Test func `Sequence emits every element`() async {
            self.sequence.yield(0)
            self.sequence.yield(1)
            self.sequence.finish(with: 2)

            let values = await self.sequence.collect()
            #expect(values == [0, 1, 2])
        }
    }
}
