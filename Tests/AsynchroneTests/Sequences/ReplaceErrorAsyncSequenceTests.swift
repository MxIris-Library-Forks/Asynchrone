import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ReplaceErrorTests {
        @Test func `Error replaced`() async {
            let replacement = 0

            let values = await Fail<Int, TestError>(
                error: TestError()
            )
            .replaceError(with: replacement)
            .collect()

            #expect(values == [replacement])
        }
    }
}
