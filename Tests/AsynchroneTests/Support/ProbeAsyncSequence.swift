import Foundation

/// An upstream async sequence that a test drives by hand and observes from the outside.
///
/// Elements and completion are sent with `send(_:)` and `finish()`, and every iterator
/// reads from the same queue. The probe also records how many iterators were made and how
/// many `next()` calls are suspended right now, which is how tests catch iterators that an
/// operator creates but never uses, and calls that it leaves waiting on its upstream.
final class ProbeAsyncSequence<Element: Sendable>: AsyncSequence, @unchecked Sendable {
    struct Iterator: AsyncIteratorProtocol, Sendable {
        fileprivate let probe: ProbeAsyncSequence<Element>

        mutating func next() async -> Element? {
            await self.probe.nextElement()
        }
    }

    // Private
    private let respondsToCancellation: Bool
    private let lock = NSLock()
    private var bufferedElements: [Element] = []
    private var isFinished = false
    private var suspendedCalls: [SuspendedCall] = []
    private var cancelledCallIdentifiers: Set<Int> = []
    private var lastCallIdentifier = 0
    private var iteratorCount = 0

    // MARK: Initialization

    /// Creates a probe.
    /// - Parameter respondsToCancellation: Whether a suspended `next()` call returns `nil`
    ///   when its task is cancelled. Pass `false` to model an upstream that ignores cancellation.
    init(respondsToCancellation: Bool = true) {
        self.respondsToCancellation = respondsToCancellation
    }

    // MARK: Observation

    /// The number of iterators made so far.
    var madeIteratorCount: Int {
        self.lock.withLock { self.iteratorCount }
    }

    /// The number of `next()` calls currently suspended waiting for an element.
    var suspendedNextCount: Int {
        self.lock.withLock { self.suspendedCalls.count }
    }

    // MARK: AsyncSequence

    func makeAsyncIterator() -> Iterator {
        self.lock.withLock { self.iteratorCount += 1 }
        return Iterator(probe: self)
    }

    // MARK: Driving

    /// Delivers `element` to the longest suspended `next()` call, or buffers it.
    func send(_ element: Element) {
        let continuation: CheckedContinuation<Element?, Never>? = self.lock.withLock {
            guard !self.suspendedCalls.isEmpty else {
                self.bufferedElements.append(element)
                return nil
            }
            return self.suspendedCalls.removeFirst().continuation
        }

        continuation?.resume(returning: element)
    }

    /// Ends the sequence. Buffered elements are still delivered, then every `next()` returns `nil`.
    func finish() {
        let continuations = self.lock.withLock {
            self.isFinished = true
            defer { self.suspendedCalls.removeAll() }
            return self.suspendedCalls.map(\.continuation)
        }

        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }

    // MARK: Iteration

    fileprivate func nextElement() async -> Element? {
        let identifier = self.lock.withLock {
            self.lastCallIdentifier += 1
            return self.lastCallIdentifier
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediateElement: Element?? = self.lock.withLock {
                    if !self.bufferedElements.isEmpty {
                        return .some(self.bufferedElements.removeFirst())
                    }

                    if self.isFinished || self.cancelledCallIdentifiers.remove(identifier) != nil {
                        return .some(nil)
                    }

                    self.suspendedCalls.append(SuspendedCall(identifier: identifier, continuation: continuation))
                    return .none
                }

                if let immediateElement {
                    continuation.resume(returning: immediateElement)
                }
            }
        } onCancel: {
            guard self.respondsToCancellation else { return }

            let continuation: CheckedContinuation<Element?, Never>? = self.lock.withLock {
                guard let index = self.suspendedCalls.firstIndex(where: { $0.identifier == identifier }) else {
                    // The call has not suspended yet; make it return as soon as it does.
                    self.cancelledCallIdentifiers.insert(identifier)
                    return nil
                }
                return self.suspendedCalls.remove(at: index).continuation
            }

            continuation?.resume(returning: nil)
        }
    }
}

// MARK: Suspended call

extension ProbeAsyncSequence {
    private struct SuspendedCall {
        let identifier: Int
        let continuation: CheckedContinuation<Element?, Never>
    }
}
