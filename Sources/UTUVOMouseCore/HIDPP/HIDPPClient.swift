import Foundation

/// A transport that carries already encoded HID++ reports.
public protocol HIDPPTransport: AnyObject, Sendable {
    /// Sends one encoded report (byte 0 is the report identifier).
    func send(_ bytes: [UInt8]) throws
    /// Installs the handler that receives complete frames (byte 0 is the report identifier).
    func setReportHandler(_ handler: @escaping @Sendable ([UInt8]) -> Void)
}

/// A FIFO async mutex.
///
/// One request at a time per transport: the wire carries one software ID per
/// transaction and a reply has to be matched to the request that asked for it.
actor AsyncGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

/// One outstanding transaction.
final class PendingResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[UInt8], any Error>?
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<[UInt8], any Error>) {
        self.continuation = continuation
    }

    /// Arms the bounded wait. `onTimeout` runs before the continuation is failed so
    /// the transaction can be taken out of the pending table first.
    func arm(timeout: Duration, key: HIDPPResponseKey, onTimeout: @escaping @Sendable () -> Void) {
        timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            onTimeout()
            self.finish(.failure(HIDPPError.timeout(featureIndex: key.featureIndex, function: key.function)))
        }
    }

    func finish(_ result: Result<[UInt8], any Error>) {
        let continuation: CheckedContinuation<[UInt8], any Error>? = lock.withLock {
            timeoutTask?.cancel()
            timeoutTask = nil
            let taken = continuation
            continuation = nil
            return taken
        }
        continuation?.resume(with: result)
    }
}

/// The table of outstanding transactions.
final class PendingResponses: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [HIDPPResponseKey: PendingResponse] = [:]

    func register(_ key: HIDPPResponseKey, _ pending: PendingResponse) {
        lock.withLock { entries[key] = pending }
    }

    func remove(_ key: HIDPPResponseKey) {
        lock.withLock { _ = entries.removeValue(forKey: key) }
    }

    func complete(_ key: HIDPPResponseKey, _ result: Result<[UInt8], any Error>) {
        let pending: PendingResponse? = lock.withLock { entries.removeValue(forKey: key) }
        pending?.finish(result)
    }
}

/// Speaks HID++ 2.0 over one transport.
///
/// Transactions are serialised: only one request is in flight per transport, and
/// every transaction carries its own software ID (1...15). A reply is matched on
/// device index, feature index, function ID *and* software ID, so a late answer
/// to an older transaction can never be taken for the current one.
public final class HIDPPClient: @unchecked Sendable {
    /// Device index this client addresses (0xFF for a directly attached device,
    /// 1...6 for a slot on a receiver).
    public let deviceIndex: UInt8
    /// Bounded wait for a reply.
    public let timeout: Duration

    private let transport: HIDPPTransport
    private let pending = PendingResponses()
    private let gate = AsyncGate()
    private let softwareIDLock = NSLock()
    private var softwareIDCounter: UInt8 = 0
    private let observerLock = NSLock()
    private var observers: [@Sendable ([UInt8]) -> Void] = []

    public init(
        transport: HIDPPTransport,
        deviceIndex: UInt8,
        timeout: Duration = .milliseconds(700)
    ) throws {
        self.transport = transport
        self.deviceIndex = deviceIndex
        self.timeout = timeout
        transport.setReportHandler { [weak self] frame in
            self?.handle(frame)
        }
    }

    /// The software ID of the next transaction. The IDs rotate through 1...15.
    public func nextSoftwareID() -> UInt8 {
        softwareIDLock.withLock {
            softwareIDCounter = softwareIDCounter == 14 ? 1 : softwareIDCounter + 1
            return softwareIDCounter
        }
    }

    /// Sends a request and waits for the matching reply.
    ///
    /// The reply is matched on device index, feature index, function ID and
    /// software ID. Device notifications (software ID 0) are ignored.
    @discardableResult
    public func request(
        featureIndex: UInt8,
        function: UInt8,
        payload: [UInt8] = [],
        shortFallback: Bool = false
    ) async throws -> [UInt8] {
        await gate.acquire()
        defer { Task { await gate.release() } }
        let softwareID = nextSoftwareID()
        let request = HIDPPRequest(
            featureIndex: featureIndex,
            function: function,
            payload: payload,
            shortFallback: shortFallback
        )
        do {
            return try await perform(request, softwareID: softwareID, reportID: .long)
        } catch let error as HIDPPError {
            if shortFallback, case .timeout = error,
               request.payload.count <= HIDPPReportID.short.payloadLength {
                return try await perform(request, softwareID: softwareID, reportID: .short)
            }
            throw error
        }
    }

    private func perform(_ request: HIDPPRequest, softwareID: UInt8, reportID: HIDPPReportID) async throws -> [UInt8] {
        let bytes = try request.encoded(deviceIndex: deviceIndex, softwareID: softwareID, reportID: reportID)
        let key = HIDPPResponseKey(
            deviceIndex: deviceIndex,
            featureIndex: request.featureIndex,
            function: request.function,
            softwareID: softwareID
        )
        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingResponse(continuation: continuation)
            // Registered before the request goes out, so a reply that arrives
            // immediately is never lost.
            self.pending.register(key, pending)
            pending.arm(timeout: timeout, key: key) { [weak self] in
                self?.pending.remove(key)
            }
            do {
                try transport.send(bytes)
            } catch {
                self.pending.complete(key, .failure(HIDPPError.transportFailure(String(describing: error))))
            }
        }
    }

    /// Registers an observer that sees every frame of this transport.
    ///
    /// Device notifications are not replies, so a feature that listens for them
    /// (for example the diverted button events of 0x1B04) uses this.
    public func addObserver(_ observer: @escaping @Sendable ([UInt8]) -> Void) {
        observerLock.withLock { observers.append(observer) }
    }

    private func handle(_ frame: [UInt8]) {
        let currentObservers = observerLock.withLock { observers }
        for observer in currentObservers { observer(frame) }
        guard let response = try? HIDPPResponse.parse(frame) else { return }
        // A device notification carries software ID 0 and never answers a request.
        guard response.softwareID != HIDPPSoftwareID.device else { return }
        let key = HIDPPResponseKey(
            deviceIndex: response.deviceIndex,
            featureIndex: response.featureIndex,
            function: response.function,
            softwareID: response.softwareID
        )
        switch response.outcome {
        case .success(let data):
            pending.complete(key, .success(data))
        case .failure(let reason):
            pending.complete(key, .failure(HIDPPError.deviceError(reason: reason)))
        }
    }
}
