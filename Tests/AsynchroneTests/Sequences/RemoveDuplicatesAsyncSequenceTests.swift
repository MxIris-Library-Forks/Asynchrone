import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct RemoveDuplicatesAsyncSequenceTests {
        private let sequence = [1, 1, 2, 2, 3, 3, 1].async.eraseToAnyAsyncSequenceable()

        @Test func `Duplicates removed`() async {
            let values = await self.sequence
                .removeDuplicates()
                .collect()

            #expect(values == [1, 2, 3, 1])
        }

        @Test func `Removing duplicates with a predicate`() async {
            let values = await self.sequence
                .removeDuplicates { previous, current in
                    previous >= current
                }
                .collect()

            #expect(values == [1, 2, 3])
        }
    }
}
