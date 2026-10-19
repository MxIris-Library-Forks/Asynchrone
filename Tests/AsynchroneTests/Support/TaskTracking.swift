/// Detects tasks that outlive the code that created them.
///
/// An unstructured task copies the task-local values of the task that creates it and
/// releases those copies when it completes. A marker bound around an operation is
/// therefore kept alive by every unstructured task the operation creates, directly or
/// through other tasks, until the last of them has finished.
enum TaskTracking {
    /// An object whose lifetime reveals whether the tasks created around it are still running.
    final class Marker: Sendable {}

    @TaskLocal static var marker: Marker? = nil

    /// Runs `operation` with a fresh marker bound.
    /// - Parameter operation: The operation whose tasks to track.
    /// - Returns: A weak reference to the marker. It becomes `nil` once every task that
    ///   `operation` created has finished.
    nonisolated(nonsending)
    static func run(
        _ operation: nonisolated(nonsending) () async throws -> Void
    ) async rethrows -> WeakReference<Marker> {
        let marker = Marker()
        try await self.$marker.withValue(marker, operation: operation)
        return WeakReference(marker)
    }
}

// MARK: Weak reference

/// A reference that does not keep its object alive.
final class WeakReference<Object: AnyObject & Sendable>: Sendable {
    weak let object: Object?

    init(_ object: Object) {
        self.object = object
    }
}
