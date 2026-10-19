import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct Merge3AsyncSequenceTests {
        private let sequenceA = [1, 4].async.eraseToAnyAsyncSequenceable()
        private let sequenceB = [2, 5, 7].async.eraseToAnyAsyncSequenceable()
        private let sequenceC = [3, 6].async.eraseToAnyAsyncSequenceable()

        @Test func `Merging three sequences`() async {
            let values = await self.sequenceA
                .merge(with: self.sequenceB, self.sequenceC)
                .collect()

            #expect(values.sorted() == [1, 2, 3, 4, 5, 6, 7])
        }
    }
}
