import Foundation
import Testing
@testable import Asynchrone

extension AsynchroneTestSuite {
    struct NotificationCenterAsyncSequenceTests {
        @Test func `Notifications are received`() async {
            let notificationCenter = NotificationCenter()

            // Making the iterator registers the observer, so nothing posted below is missed.
            var iterator = notificationCenter
                .sequence(for: .testNotification)
                .makeAsyncIterator()

            notificationCenter.post(name: .testNotification, object: 1)
            notificationCenter.post(name: .testNotification, object: 2)

            let firstObject = await iterator.next()?.object as? Int
            let secondObject = await iterator.next()?.object as? Int
            #expect(firstObject == 1)
            #expect(secondObject == 2)
        }

        @Test func `Stopping early removes the observer`() async {
            let notificationCenter = ObserverRemovalCountingNotificationCenter()

            do {
                var iterator = notificationCenter
                    .sequence(for: .testNotification)
                    .makeAsyncIterator()

                notificationCenter.post(name: .testNotification, object: nil)
                _ = await iterator.next()
            }

            #expect(await eventually(timeout: 1) { notificationCenter.removedObserverCount > 0 })
        }
    }
}

// MARK: Notification name

private extension Notification.Name {
    static let testNotification = Notification.Name("testNotification")
}

// MARK: ObserverRemovalCountingNotificationCenter

/// A notification center that counts how many observers have been removed from it.
private final class ObserverRemovalCountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var removalCount = 0

    var removedObserverCount: Int {
        self.lock.withLock { self.removalCount }
    }

    override func removeObserver(_ observer: Any) {
        self.lock.withLock { self.removalCount += 1 }
        super.removeObserver(observer)
    }
}
