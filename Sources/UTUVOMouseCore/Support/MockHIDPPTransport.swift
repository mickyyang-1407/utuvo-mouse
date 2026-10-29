import Foundation

/// A transport that answers requests from a scripted responder.
///
/// Used by the tests and by the demo mode — it never touches hardware.
public final class MockHIDPPTransport: HIDPPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable ([UInt8]) -> Void)?
    private var responder: @Sendable ([UInt8]) -> [UInt8]?
    private var frames: [[UInt8]] = []

    /// - Parameter responder: receives the encoded request and returns the frame the
    ///   device would answer with, or `nil` to stay silent (a timeout).
    public init(responder: @escaping @Sendable ([UInt8]) -> [UInt8]?) {
        self.responder = responder
    }

    /// Every frame this transport was asked to send.
    public var sentFrames: [[UInt8]] { lock.withLock { frames } }

    public func send(_ bytes: [UInt8]) throws {
        lock.withLock { frames.append(bytes) }
        guard let reply = responder(bytes) else { return }
        let handler = lock.withLock { self.handler }
        handler?(reply)
    }

    public func setReportHandler(_ handler: @escaping @Sendable ([UInt8]) -> Void) {
        lock.withLock { self.handler = handler }
    }

    /// Delivers a frame that was not the answer to a request (a notification).
    public func deliver(_ frame: [UInt8]) {
        let handler = lock.withLock { self.handler }
        handler?(frame)
    }
}
