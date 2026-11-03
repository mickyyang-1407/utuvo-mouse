/// When to read the devices again on its own: a receiver with no reachable
/// mouse (usually asleep), or a supported mouse whose read was incomplete.
public enum WakeRetryPolicy {
    public static let interval: Double = 30
    public static let maxIncompleteReadRetries = 10

    /// - Parameters:
    ///   - receiverWaiting: a receiver is present but no mouse answered (one ping per retry, not bounded).
    ///   - incompleteRead: a supported mouse answered only part of the read (bounded).
    ///   - retries: consecutive incomplete reads so far.
    ///   - afterRead: true when called right after a real read, which is the only thing that counts.
    public static func decide(receiverWaiting: Bool, incompleteRead: Bool, retries: Int, afterRead: Bool) -> (retry: Bool, retries: Int) {
        let count = afterRead ? (incompleteRead ? retries + 1 : 0) : retries
        return (receiverWaiting || (incompleteRead && count <= maxIncompleteReadRetries), count)
    }
}
