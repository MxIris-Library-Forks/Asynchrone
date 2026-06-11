import Foundation

/// An async sequence that emits the current date on a given interval.
///
/// This sequence supports a single consumer. Use `shared()` to broadcast
/// to multiple consumers.
///
/// ```swift
/// let sequence = TimerAsyncSequence(interval: 1)
///
/// for await element in sequence {
///     print(element)
/// }
///
/// // Prints:
/// // 2022-03-19 20:49:30 +0000
/// // 2022-03-19 20:49:31 +0000
/// // 2022-03-19 20:49:32 +0000
/// ```
public final class TimerAsyncSequence: AsyncSequence, @unchecked Sendable {
    /// The kind of elements streamed.
    public typealias Element = Date

    // Private
    private let interval: TimeInterval
    private let passthroughSequence: PassthroughAsyncSequence<Element> = .init()
    private let lock: NSLock = .init()
    private var task: Task<Void, Never>?
    private var hasStarted = false
    private var isCancelled = false

    // MARK: Initialization

    /// Creates an async sequence that emits the current date on a given interval.
    ///
    /// Negative intervals are treated as zero.
    /// - Parameters:
    ///   - interval: The interval on which to emit elements.
    public init(interval: TimeInterval) {
        self.interval = Swift.max(0, interval)
    }

    // MARK: Timer

    private func startIfNeeded() {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard !self.hasStarted else { return }
        self.hasStarted = true

        // cancel() was called before the first iteration began.
        guard !self.isCancelled else {
            self.passthroughSequence.finish()
            return
        }

        self.task = Task { [interval, passthroughSequence] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(seconds: interval)
                    passthroughSequence.yield(Date())
                } catch {
                    // Task.sleep only throws CancellationError.
                    break
                }
            }
            // Always finish, regardless of how the loop exits.
            passthroughSequence.finish()
        }
    }

    /// Cancel the sequence from emitting anymore elements.
    public func cancel() {
        self.lock.lock()
        self.isCancelled = true
        let runningTask = self.task
        self.task = nil
        let shouldFinish = self.hasStarted && runningTask == nil
        self.lock.unlock()

        runningTask?.cancel()
        if shouldFinish {
            self.passthroughSequence.finish()
        }
    }

    // MARK: AsyncSequence

    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> PassthroughAsyncSequence<Element>.AsyncIterator {
        defer { self.startIfNeeded() }
        return self.passthroughSequence.makeAsyncIterator()
    }
}
