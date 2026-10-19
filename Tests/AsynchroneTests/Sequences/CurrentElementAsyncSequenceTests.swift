import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct CurrentElementAsyncSequenceTests {
        private let sequence = CurrentElementAsyncSequence(0)

        @Test func `Current element`() async {
            var element = await self.sequence.element
            #expect(element == 0)

            await self.sequence.yield(1)
            element = await self.sequence.element
            #expect(element == 1)

            await self.sequence.yield(2)
            await self.sequence.yield(3)
            await self.sequence.yield(4)
            element = await self.sequence.element
            #expect(element == 4)
        }

        @Test func `Sequence emits every element`() async {
            await self.sequence.yield(1)
            await self.sequence.finish(with: 2)

            let values = await self.sequence.collect()
            #expect(values == [0, 1, 2])
        }

        @Test func `Yielding after finishing does not change the element`() async {
            await self.sequence.finish()
            await self.sequence.yield(1)
            await self.sequence.finish(with: 2)

            let element = await self.sequence.element
            #expect(element == 0)
        }
    }
}
