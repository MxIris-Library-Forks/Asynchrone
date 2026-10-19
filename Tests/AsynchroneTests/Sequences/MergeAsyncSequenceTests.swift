import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct MergeAsyncSequenceTests {
        private let sequenceA = [1, 2, 3, 4].async.eraseToAnyAsyncSequenceable()
        private let sequenceB = [5, 6, 7, 8, 9].async.eraseToAnyAsyncSequenceable()

        @Test func `Merging two sequences`() async {
            let values = await self.sequenceA
                .merge(with: self.sequenceB)
                .collect()

            #expect(values.sorted() == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        }
    }
}
