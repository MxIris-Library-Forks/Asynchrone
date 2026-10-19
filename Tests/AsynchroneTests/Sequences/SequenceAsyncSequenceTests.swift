import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct SequenceAsyncSequenceTests {
        @Test func `Creating an async sequence`() async {
            let array = [0, 1, 2, 3]
            let values = await array.async.collect()
            #expect(values == array)
        }
    }
}
