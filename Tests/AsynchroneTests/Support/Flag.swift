import Foundation

/// A thread-safe flag that a callback sets and a test checks later.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    /// Whether `set()` has been called.
    var isSet: Bool {
        self.lock.withLock { self.storage }
    }

    func set() {
        self.lock.withLock { self.storage = true }
    }
}
