import Foundation

/// An async sequence that emits when a notification center broadcasts notifications.
///
/// ```swift
/// let sequence = NotificationCenterAsyncSequence(
///     notificationCenter: .default,
///     notificationName: UIDevice.orientationDidChangeNotification,
///     object: nil
/// )
///
/// for await element in sequence {
///     print(element)
/// }
///
/// ```
public struct NotificationCenterAsyncSequence: AsyncSequence {
    /// The kind of elements streamed.
    public typealias Element = Notification

    // Private
    private var notificationCenter: NotificationCenter
    private var notificationName: Notification.Name
    private var object: AnyObject?

    // MARK: Initialization

    public init(
        notificationCenter: NotificationCenter,
        notificationName: Notification.Name,
        object: AnyObject? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.object = object
    }
        
    // MARK: AsyncSequence
    
    /// Creates an async iterator that emits elements of this async sequence.
    /// - Returns: An instance that conforms to `AsyncIteratorProtocol`.
    public func makeAsyncIterator() -> Iterator {
        .init(
            notificationCenter: self.notificationCenter,
            notificationName: self.notificationName,
            object: self.object
        )
    }
}

// MARK: Iterator

extension NotificationCenterAsyncSequence {
    public struct Iterator: AsyncIteratorProtocol {
        private var iterator: AsyncStream<Notification>.Iterator

        // MARK: Initialization

        init(
            notificationCenter: NotificationCenter,
            notificationName: Notification.Name,
            object: AnyObject? = nil
        ) {
            let (stream, continuation) = AsyncStream<Notification>.makeStream()

            // Notification is not Sendable. NotificationCenter serialises
            // delivery per observer, which makes handing the notification over
            // to the stream safe in practice.
            //
            // The block captures only the continuation. Capturing the stream
            // would keep it alive for as long as the observer is registered,
            // so the stream would never terminate and remove the observer.
            let observer = notificationCenter.addObserver(
                forName: notificationName,
                object: object,
                queue: nil
            ) { notification in
                nonisolated(unsafe) let notification = notification
                continuation.yield(notification)
            }

            // The stream terminates when its consumer stops: when the consuming
            // task is cancelled, or when the last copy of this iterator is
            // released after an early `break` or `first()`.
            nonisolated(unsafe) let observerToRemove = observer
            continuation.onTermination = { @Sendable _ in
                notificationCenter.removeObserver(observerToRemove)
            }

            self.iterator = stream.makeAsyncIterator()
        }

        // MARK: AsyncIteratorProtocol

        public mutating func next() async -> Element? {
            await self.iterator.next()
        }
    }
}

// MARK: Notification center

extension NotificationCenter {
    /// Returns an async sequence that emits when the notification
    /// center broadcasts notifications.
    ///
    /// ```swift
    /// let sequence = NotificationCenter.default.sequence(for: UIDevice.orientationDidChangeNotification)
    ///
    /// for await element in sequence {
    ///     print(element)
    /// }
    ///
    /// ```
    public func sequence(
        for name: Notification.Name,
        object: AnyObject? = nil
    ) -> NotificationCenterAsyncSequence {
        .init(
            notificationCenter: self,
            notificationName: name,
            object: object
        )
    }
}
