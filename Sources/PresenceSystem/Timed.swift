import Foundation

/// Runs one blocking read on its own serial queue and waits for it with a deadline.
///
/// A read that misses its deadline is abandoned, not cancelled: it keeps running on
/// its queue, and the next call waits for that same read instead of stacking another
/// one behind it. So a wedged system service costs at most one stuck thread per probe,
/// and the caller never blocks longer than the deadline.
final class TimedProbe<Value>: @unchecked Sendable {
    private final class Pending: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        var value: Value?
    }

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: Pending?
    private let body: () -> Value?

    init(_ label: String, body: @escaping () -> Value?) {
        queue = DispatchQueue(label: "presence.probe.\(label)", qos: .userInitiated)
        self.body = body
    }

    /// The value, or nil when the read failed or did not answer within `timeoutMs`.
    func read(timeoutMs: Int) -> Value? {
        lock.lock()
        let current: Pending
        if let inFlight = pending {
            current = inFlight
        } else {
            current = Pending()
            pending = current
            queue.async { [self] in
                let value = body()
                lock.lock()
                current.value = value
                if pending === current { pending = nil }
                lock.unlock()
                current.done.signal()
            }
        }
        lock.unlock()
        guard current.done.wait(timeout: .now() + .milliseconds(max(1, timeoutMs))) == .success else { return nil }
        // Let any other waiter on the same read through too.
        current.done.signal()
        lock.lock()
        defer { lock.unlock() }
        return current.value
    }
}
