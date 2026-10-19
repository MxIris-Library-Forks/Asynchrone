import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct EmptyTests {
        @Test func `Nothing emitted`() async {
            let values = await Empty<Int>().collect()
            #expect(values == [])
        }

        @Test func `Sequence does not complete`() async throws {
            let values = try await result(within: 1) {
                await Empty<Int>(completeImmediately: false).collect()
            }

            #expect(values == nil)
        }
    }
}
