import Foundation

/// Polls `condition` until it holds or `timeout` elapses.
///
/// Use it to wait for an effect that happens on another task before asserting on the
/// observed state, or wrap it in `#expect` when the condition is the assertion itself.
///
/// - Parameters:
///   - timeout: The number of seconds to keep polling for.
///   - condition: The condition to poll.
/// - Returns: Whether the condition held before the timeout elapsed.
@discardableResult
nonisolated(nonsending)
func eventually(
    timeout: TimeInterval = 5,
    _ condition: nonisolated(nonsending) () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))

    while true {
        if await condition() {
            return true
        }

        if clock.now >= deadline || Task.isCancelled {
            return false
        }

        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Runs `operation` and returns its result, or `nil` if it does not finish within `timeout`.
///
/// The operation runs in its own task, which is cancelled when the timeout elapses. The call
/// returns at the timeout even if the operation ignores cancellation, so an operation that
/// hangs shows up as a failed expectation instead of a stuck test run.
///
/// - Parameters:
///   - timeout: The number of seconds the operation may take.
///   - operation: The operation to run.
/// - Returns: The result of the operation, or `nil` if the timeout elapsed first.
func result<Value: Sendable>(
    within timeout: TimeInterval,
    of operation: @escaping @Sendable () async throws -> Value
) async throws -> Value? {
    try await withCheckedThrowingContinuation { continuation in
        let race = FirstOutcomeRace(continuation)

        let operationTask = Task {
            do {
                race.finish(with: .success(try await operation()))
            } catch {
                race.finish(with: .failure(error))
            }
        }

        race.setTimeoutTask(
            Task {
                guard (try? await Task.sleep(for: .seconds(timeout))) != nil else { return }
                operationTask.cancel()
                race.finish(with: .success(nil))
            }
        )
    }
}

// MARK: First outcome race

/// Hands the first outcome of an operation racing a timeout to a continuation, exactly once.
private final class FirstOutcomeRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value?, Error>) {
        self.continuation = continuation
    }

    /// Stores the timeout task so that an outcome arriving first can cancel it.
    func setTimeoutTask(_ task: Task<Void, Never>) {
        let isAlreadyFinished = self.lock.withLock {
            guard self.continuation != nil else { return true }
            self.timeoutTask = task
            return false
        }

        if isAlreadyFinished {
            task.cancel()
        }
    }

    func finish(with outcome: Result<Value?, Error>) {
        let (continuation, timeoutTask) = self.lock.withLock {
            defer {
                self.continuation = nil
                self.timeoutTask = nil
            }
            return (self.continuation, self.timeoutTask)
        }

        timeoutTask?.cancel()
        continuation?.resume(with: outcome)
    }
}
