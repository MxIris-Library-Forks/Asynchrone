import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct JustTests {
        @Test func `Emitted elements`() async {
            let values = await Just(1).collect()
            #expect(values == [1])
        }
    }
}
