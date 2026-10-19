import Foundation

extension Task where Success == Never, Failure == Never {
    
    /// Suspends the current task for at least the given duration in seconds.
    ///
    /// If the task is canceled before the time ends, this function throws CancellationError.
    /// This function doesn’t block the underlying thread.
    ///
    /// Negative durations are treated as zero. Durations too long to represent in
    /// nanoseconds, such as `.infinity`, are limited to the longest one that can be,
    /// which is more than 584 years.
    /// - Parameter duration: The number of seconds to suspend the current task for.
    public static func sleep(seconds duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: duration.clampedNanoseconds)
    }
}
