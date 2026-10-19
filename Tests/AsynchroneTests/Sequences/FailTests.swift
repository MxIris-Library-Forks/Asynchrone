import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct FailTests {
        @Test func `Error thrown`() async {
            await #expect(throws: TestError.self) {
                _ = try await Fail<Int, TestError>(
                    error: TestError()
                ).collect()
            }
        }

        @Test func `Error only thrown once`() async {
            let replacement = 0
            let values = await Fail<Int, TestError>(
                error: TestError()
            )
            .replaceError(with: replacement)
            .collect()

            #expect(values == [0])
        }
    }
}
