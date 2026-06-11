/// Coordinates a race between tasks, recording the first task to cross the line.
internal actor TaskRaceCoordinator<Success, Failure: Error> where Success: Sendable {
    private var winner: Task<Success, Failure>?

    func isFirstToCrossLine(_ task: Task<Success, Failure>) -> Bool {
        guard self.winner == nil else { return false }
        self.winner = task
        return true
    }
}

// MARK: First to complete

extension Task where Success: Sendable {
    /// Awaits the provided tasks and returns the first one to complete.
    ///
    /// If the surrounding task is cancelled, all racing tasks are cancelled.
    /// - Parameter tasks: The tasks to race.
    /// - Returns: The first task to complete.
    internal static func firstToComplete(of tasks: [Task<Success, Failure>]) async -> Task<Success, Failure> {
        let raceCoordinator = TaskRaceCoordinator<Success, Failure>()
        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    for task in tasks {
                        Task<Void, Never> {
                            _ = await task.result
                            if await raceCoordinator.isFirstToCrossLine(task) {
                                continuation.resume(returning: task)
                            }
                        }
                    }
                }
            },
            onCancel: {
                for task in tasks {
                    task.cancel()
                }
            }
        )
    }
}
