import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct ThrowingZipAsyncSequenceTests {
        @Test func `Zipping four sequences`() async throws {
            let values = try await [1, 2, 3].async
                .zip(["a", "b", "c"].async, [true, false].async, [5, 6, 7].async)
                .collect()
                .map { "\($0.0)-\($0.1)-\($0.2)-\($0.3)" }

            #expect(values == ["1-a-true-5", "2-b-false-6"])
        }

        @Test func `Destructuring three elements in the loop header`() async throws {
            var values: [String] = []
            for try await (number, letter, flag) in [1, 2].async.tryZip(["a", "b"].async, [true, false].async) {
                values.append("\(number)-\(letter)-\(flag)")
            }

            #expect(values == ["1-a-true", "2-b-false"])
        }

        @Test func `tryZip throws an error from a later sequence`() async {
            let numbers = [1, 2].async
            let words = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("a")
                continuation.finish(throwing: TestError())
            }

            await #expect(throws: TestError.self) {
                _ = try await numbers.tryZip(words).collect()
            }
        }

        @Test func `Zip stops at the first sequence that finishes`() async throws {
            // These probes never finish, so advancing them a second time would suspend forever.
            let third = ProbeAsyncSequence<Int>()
            let fourth = ProbeAsyncSequence<Int>()
            third.send(8)
            fourth.send(9)

            let count = try await result(within: 5) {
                try await [1, 2].async
                    .zip([5].async, third, fourth)
                    .collect()
                    .count
            }

            #expect(count == 1)
        }

        @Test func `An error ends the sequence without advancing it again`() async throws {
            let numbers = ProbeAsyncSequence<Int>()
            numbers.send(1)
            numbers.send(2)
            let words = AsyncThrowingStream<String, Error> { continuation in
                continuation.finish(throwing: TestError())
            }

            var iterator = numbers.tryZip(words).makeAsyncIterator()
            await #expect(throws: TestError.self) {
                _ = try await iterator.next()
            }
            let elementAfterError = try await iterator.next()

            numbers.finish()
            var numbersIterator = numbers.makeAsyncIterator()
            let remainingNumber = await numbersIterator.next()

            #expect(elementAfterError == nil)
            #expect(remainingNumber == 2)
        }

        @Test func `Iterating creates exactly one iterator of each sequence`() async throws {
            let probes = (0..<4).map { _ in ProbeAsyncSequence<Int>() }
            for probe in probes {
                probe.send(1)
                probe.finish()
            }

            let values = try await probes[0]
                .zip(probes[1], probes[2], probes[3])
                .collect()

            #expect(values.count == 1)
            #expect(probes.map(\.madeIteratorCount) == [1, 1, 1, 1])
        }

        @Test func `Zipped sequence is sendable when every sequence is`() async throws {
            let sequence = [1, 2].async.zip(["a", "b"].async, [true, false].async)

            #expect(try await elementCount(of: sequence) == 2)
        }

        @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, watchOS 11, visionOS 2, *)
        @Test func `Iterating two zipped sequences when one can throw`() async throws {
            let numbers = [1, 2].async
            let words = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("a")
                continuation.yield("b")
                continuation.finish()
            }

            var values: [String] = []
            for try await (number, word) in numbers.zip(words) {
                values.append("\(number)-\(word)")
            }

            #expect(values == ["1-a", "2-b"])
        }
    }
}

/// Counts the elements of `sequence`. Accepting only `Sendable` sequences makes a call
/// compile only while the sequence passed in is `Sendable`.
private func elementCount<Base: AsyncSequence & Sendable>(of sequence: Base) async throws -> Int {
    try await sequence.collect().count
}
