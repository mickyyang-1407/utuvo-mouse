import Foundation
import Testing
import UTUVOMouseCore
import UTUVOMouseIO

/// Synthetic reports only. No service construction, IOKit discovery, filesystem,
/// user defaults or hardware access is performed by this suite.
@Suite("M016 MX Anywhere 3 opt-in capability inspection — mocks only")
struct MXAnywhere3CapabilityInspectionTests {
    private let identity = CapabilityInspectionIdentity(vendorID: 0x046D, productID: 0xB025, transport: .bluetooth)

    @Test("Missing consent and wrong vendor/PID/transport never invoke the opener or send a request")
    func deniedGates() async {
        let denied: [(CapabilityInspectionIdentity, Bool, CapabilityInspectionError)] = [
            (identity, false, .consentRequired),
            (.init(vendorID: 0x1234, productID: 0xB025, transport: .bluetooth), true, .identityMismatch),
            (.init(vendorID: 0x046D, productID: 0xB023, transport: .bluetooth), true, .identityMismatch),
            (.init(vendorID: 0x046D, productID: 0xB025, transport: .usb), true, .identityMismatch),
            (.init(vendorID: 0x046D, productID: 0xB025, transport: .receiver), true, .identityMismatch),
            (.init(vendorID: 0x046D, productID: 0xB025, transport: .unknown), true, .identityMismatch),
            (.init(vendorID: 0x046D, productID: 0xC52B, transport: .receiver), true, .identityMismatch),
            (.init(vendorID: 0x046D, productID: 0x4090, transport: .receiver), true, .identityMismatch),
        ]
        for (candidate, consent, expected) in denied {
            let opener = InspectionFixtureOpener()
            await expectFailure(expected, identity: candidate, consent: consent, opener: opener)
            #expect(opener.openCount == 0)
            #expect(opener.channel.sentFrames.isEmpty)
            #expect(opener.channel.closeCount == 0)
        }
    }

    @Test("Only exact Bluetooth registry strings on a mouse collection qualify")
    func interfaceGate() throws {
        for transport in ["Bluetooth", "Bluetooth Low Energy"] {
            #expect(try MXAnywhere3InspectionInterfacePolicy.identity(vendorID: 0x046D, productID: 0xB025,
                registryTransport: transport, usagePage: 1, usage: 2) == identity)
        }
        for transport in ["", "USB", "BluetoothReceiver", "Bluetooth Fake", "unknown"] {
            #expect(throws: CapabilityInspectionError.identityMismatch) {
                try MXAnywhere3InspectionInterfacePolicy.identity(vendorID: 0x046D, productID: 0xB025,
                    registryTransport: transport, usagePage: 1, usage: 2)
            }
        }
        for (vendor, product, page, usage) in [(0x1234, 0xB025, 1, 2), (0x046D, 0xB034, 1, 2),
                                               (0x046D, 0xB025, 0xFF43, 1), (0x046D, 0xB025, 1, 6)] {
            #expect(throws: CapabilityInspectionError.identityMismatch) {
                try MXAnywhere3InspectionInterfacePolicy.identity(vendorID: vendor, productID: product,
                    registryTransport: "Bluetooth", usagePage: page, usage: usage)
            }
        }
    }

    @Test("Inspection arguments are consumed before GUI/probe routing and require an exact opt-in")
    func commandGate() throws {
        let command = CapabilityInspectionInvocation.command
        let consent = CapabilityInspectionInvocation.consent
        let key = MXAnywhere3CapabilityInspection.modelKey
        #expect(try CapabilityInspectionInvocation.parse([]) == .notRequested)
        #expect(try CapabilityInspectionInvocation.parse(["--probe"]) == .notRequested)
        #expect(try CapabilityInspectionInvocation.parse([command, "--help"]) == .help)
        #expect(try CapabilityInspectionInvocation.parse([command, key, consent]) == .inspect)
        for arguments in [[command], [command, key], [command + "=" + key], [consent + "=true"]] {
            #expect(throws: CapabilityInspectionError.consentRequired) {
                try CapabilityInspectionInvocation.parse(arguments)
            }
        }
        for arguments in [[consent], [command, "046d-b025-usb", consent], [command, "046d-c52b-receiver", consent],
                          [command, key, consent, "--probe"], [command, key, consent, "--demo"],
                          [command, key, consent, "--help"], [command, key, consent, consent]] {
            #expect(throws: CapabilityInspectionError.invalidArguments) {
                try CapabilityInspectionInvocation.parse(arguments)
            }
        }
    }

    @Test("Enumeration discovers the feature-set index and sends only four getter shapes")
    func completeReadOnlyCollection() async throws {
        let opener = InspectionFixtureOpener()
        let report = try await MXAnywhere3CapabilityInspection.collect(identity: identity, consent: true) { try opener.open() }
        #expect(report.protocolVersion.major == 4)
        #expect(report.protocolVersion.minor == 5)
        #expect(report.featureIDs == ["0000", "0001", "1B04", "2111", "2121", "2201"])
        #expect(!report.configurationWritesEnabled)
        #expect(opener.openCount == 1)
        #expect(opener.channel.closeCount == 1)
        let frames = opener.channel.sentFrames
        #expect(frames.count == 8) // version + resolve + count + five indexes (ROOT excluded)
        #expect(frames.allSatisfy { $0.count == 20 && $0[0] == 0x11 && $0[1] == 0xFF && $0[3] & 0x0F != 0 })
        #expect(frames.map { $0[2] } == [0, 0, 2, 2, 2, 2, 2, 2])
        #expect(frames.map { $0[3] >> 4 } == [1, 0, 0, 1, 1, 1, 1, 1])
        #expect(frames[0][4] == 0 && frames[0][5] == 0 && frames[0][6] != 0)
        #expect(Array(frames[1][4...6]) == [0, 1, 0])
        #expect(frames[2].dropFirst(4).allSatisfy { $0 == 0 })
        #expect(frames.dropFirst(3).map { $0[4] } == [1, 2, 3, 4, 5])
        #expect(frames.dropFirst(3).allSatisfy { $0.dropFirst(5).allSatisfy { $0 == 0 } })
    }

    @Test("The report schema exports only model IDs, transport, version, feature IDs and fixed policy fields")
    func privateOutput() async throws {
        let opener = InspectionFixtureOpener()
        let report = try await MXAnywhere3CapabilityInspection.collect(identity: identity, consent: true) { try opener.open() }
        let data = try JSONEncoder().encode(report)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "modelKey", "vendorID", "productID", "transport", "readOnly",
                                     "configurationWritesEnabled", "protocolVersion", "featureIDs"])
        #expect(object["modelKey"] as? String == "046d-b025-bluetooth")
        #expect(object["vendorID"] as? Int == 1133)
        #expect(object["productID"] as? Int == 45093)
        #expect(object["transport"] as? String == "bluetooth")
        // Even research-expected features come solely from replies, not the seed.
        let minimal = InspectionFixtureOpener(responder: { request in
            if request[2] == 2 && request[3] >> 4 == 0 { return inspectionReply(request, [2]) }
            return inspectionFixtureReply(request)
        })
        let minimalReport = try await MXAnywhere3CapabilityInspection.collect(identity: identity, consent: true) { try minimal.open() }
        #expect(minimalReport.featureIDs == ["0000", "0001", "2201"])
        #expect(!minimalReport.featureIDs.contains("1B04"))
    }

    @Test("Unavailable, denied and arbitrary opener errors never send requests or report success")
    func openFailures() async {
        for expected in [CapabilityInspectionError.unavailable, .accessDenied, .ambiguousDevice] {
            let opener = InspectionFixtureOpener(openError: expected)
            await expectFailure(expected, opener: opener)
            #expect(opener.openCount == 1)
            #expect(opener.channel.sentFrames.isEmpty)
        }
        let opener = InspectionFixtureOpener(openError: HIDPPError.transportFailure("PRIVATE-SERIAL-AND-NAME"))
        await expectFailure(.transportFailure, opener: opener)
        #expect(opener.channel.sentFrames.isEmpty)
    }

    @Test("Silence, truncation, notification and unrelated replies time out without retry or partial success")
    func invalidWireReplies() async {
        let responders: [@Sendable ([UInt8]) -> [UInt8]?] = [
            { _ in nil },
            { r in Array(inspectionFixtureReply(r)!.dropLast()) },
            { r in var reply = inspectionFixtureReply(r)!; reply[3] &= 0xF0; return reply },
            { r in var reply = inspectionFixtureReply(r)!; reply[1] = 1; return reply },
            { r in var reply = inspectionFixtureReply(r)!; reply[2] = 9; return reply },
        ]
        for responder in responders {
            let opener = InspectionFixtureOpener(responder: responder)
            await expectFailure(.timeout, opener: opener)
            #expect(opener.channel.sentFrames.count == 1)
            #expect(opener.channel.closeCount == 1)
        }
        // Failure late in enumeration must discard the already-read feature IDs.
        let late = InspectionFixtureOpener(responder: { r in
            if r[2] == 2 && r[3] >> 4 == 1 && r[4] == 5 { return nil }
            return inspectionFixtureReply(r)
        })
        await expectFailure(.timeout, opener: late)
        #expect(late.channel.sentFrames.count == 8)
        #expect(late.channel.closeCount == 1)
    }

    @Test("Bad ping echoes, counts, duplicate IDs and inconsistent feature tables fail closed")
    func malformedPayloads() async {
        let responders: [@Sendable ([UInt8]) -> [UInt8]?] = [
            { r in r[2] == 0 && r[3] >> 4 == 1 ? inspectionReply(r, [4, 5, r[6] ^ 0xFF]) : inspectionFixtureReply(r) },
            { r in r[2] == 0 && r[3] >> 4 == 1 ? inspectionReply(r, [4, 255, r[6]]) : inspectionFixtureReply(r) },
            { r in r[2] == 0 && r[3] >> 4 == 0 ? inspectionReply(r, [0xFF, 0, 0]) : inspectionFixtureReply(r) },
            { r in r[2] == 2 && r[3] >> 4 == 0 ? inspectionReply(r, [0]) : inspectionFixtureReply(r) },
            { r in r[2] == 2 && r[3] >> 4 == 0 ? inspectionReply(r, [1]) : inspectionFixtureReply(r) },
            { r in r[2] == 2 && r[3] >> 4 == 1 && r[4] == 3 ? inspectionReply(r, [0x22, 1, 0]) : inspectionFixtureReply(r) },
            { r in r[2] == 2 && r[3] >> 4 == 1 && r[4] == 2 ? inspectionReply(r, [0x22, 2, 0]) : inspectionFixtureReply(r) },
            { r in r[2] == 2 && r[3] >> 4 == 1 && r[4] == 3 ? inspectionReply(r, [0, 0, 0]) : inspectionFixtureReply(r) },
        ]
        for responder in responders {
            let opener = InspectionFixtureOpener(responder: responder)
            await expectFailure(.malformedReply, opener: opener)
            #expect(opener.channel.sentFrames.count <= 6)
            #expect(opener.channel.closeCount == 1)
        }
    }

    @Test("Unsupported protocol, absent FEATURE_SET, device errors and over-limit counts are explicit failures")
    func rejectedCapabilities() async {
        let cases: [(CapabilityInspectionError, @Sendable ([UInt8]) -> [UInt8]?)] = [
            (.unsupportedProtocol, { r in inspectionReply(r, [1, 0, r[6]]) }),
            (.featureSetUnavailable, { r in
                r[2] == 0 && r[3] >> 4 == 0 ? inspectionReply(r, [0, 0, 0]) : inspectionFixtureReply(r)
            }),
            (.featureLimitExceeded, { r in
                r[2] == 2 && r[3] >> 4 == 0 ? inspectionReply(r, [65]) : inspectionFixtureReply(r)
            }),
            (.deviceRejected, { r in [0x11, r[1], 0xFF, r[2], r[3], 2] + Array(repeating: 0, count: 14) }),
        ]
        for (expected, responder) in cases {
            let opener = InspectionFixtureOpener(responder: responder)
            await expectFailure(expected, opener: opener)
            #expect(opener.channel.sentFrames.count <= 3)
            #expect(opener.channel.closeCount == 1)
        }
    }

    @Test("Maximum feature count is bounded and unknown IDs are retained without invoking their features")
    func boundedCollection() async throws {
        let opener = InspectionFixtureOpener(responder: { r in
            guard r[2] == 2 else { return inspectionFixtureReply(r) }
            if r[3] >> 4 == 0 { return inspectionReply(r, [64]) }
            return r[4] == 2 ? inspectionReply(r, [0, 1, 0]) : inspectionReply(r, [0x90, r[4], 0x40])
        })
        let report = try await MXAnywhere3CapabilityInspection.collect(identity: identity, consent: true) { try opener.open() }
        #expect(report.featureIDs.count == 65)
        #expect(report.featureIDs.contains("9040"))
        #expect(opener.channel.sentFrames.count == MXAnywhere3CapabilityInspection.maximumRequestCount)
        #expect(opener.channel.sentFrames.allSatisfy { $0[2] == 0 || $0[2] == 2 })
        #expect(opener.channel.closeCount == 1)
    }

    @Test("Invalid timeout limits fail before opening; cancellation before collection also sends nothing")
    func invalidLimitsAndCancellation() async {
        for timeout in [Duration.zero, .milliseconds(-1), .seconds(1)] {
            let opener = InspectionFixtureOpener()
            await expectFailure(.invalidTimeout, opener: opener, timeout: timeout)
            #expect(opener.openCount == 0)
            #expect(opener.channel.sentFrames.isEmpty)
        }
        let opener = InspectionFixtureOpener()
        let identity = self.identity
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await MXAnywhere3CapabilityInspection.collect(identity: identity, consent: true) { try opener.open() }
                Issue.record("Cancelled inspection unexpectedly succeeded")
            } catch {
                #expect(error as? CapabilityInspectionError == .cancelled)
            }
        }
        await task.value
        #expect(opener.openCount == 0)
        #expect(opener.channel.sentFrames.isEmpty)
    }

    @Test("Capability inspection never promotes the new model into configuration support")
    func existingSupportUnchanged() {
        #expect(!TargetProducts.allowed.contains(0xB025))
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xB025) == .unknown)
        #expect(!MouseIdentification.model(vendorID: 0x046D, productID: 0xB025).supportsConfiguration)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xB042) == .mxMaster4)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC0A8) == .superstrike)
    }

    private func expectFailure(
        _ expected: CapabilityInspectionError, identity: CapabilityInspectionIdentity? = nil, consent: Bool = true,
        opener: InspectionFixtureOpener, timeout: Duration = .milliseconds(10)
    ) async {
        do {
            _ = try await MXAnywhere3CapabilityInspection.collect(
                identity: identity ?? self.identity, consent: consent, replyTimeout: timeout
            ) { try opener.open() }
            Issue.record("An invalid inspection unexpectedly returned a report")
        } catch {
            #expect(error as? CapabilityInspectionError == expected)
        }
    }
}

private func inspectionReply(_ request: [UInt8], _ data: [UInt8]) -> [UInt8] {
    [0x11, request[1], request[2], request[3]] + data + Array(repeating: 0, count: 16 - data.count)
}

/// Five features, with FEATURE_SET deliberately at index 2. This is synthetic,
/// not a replay or a statement about a local device's features or protocol.
private func inspectionFixtureReply(_ request: [UInt8]) -> [UInt8]? {
    let function = request[3] >> 4
    if request[2] == 0 && function == 1 { return inspectionReply(request, [4, 5, request[6]]) }
    if request[2] == 0 && function == 0 { return inspectionReply(request, [2, 0, 0]) }
    if request[2] == 2 && function == 0 { return inspectionReply(request, [5]) }
    if request[2] == 2 && function == 1, (1...5).contains(request[4]) {
        let features: [[UInt8]] = [[0x22, 1, 0], [0, 1, 0], [0x21, 0x11, 0], [0x21, 0x21, 0], [0x1B, 4, 0]]
        return inspectionReply(request, features[Int(request[4]) - 1])
    }
    return nil
}

private final class InspectionFixtureChannel: CapabilityInspectionChannel, @unchecked Sendable {
    private let mock: MockHIDPPTransport
    private let lock = NSLock()
    private var closes = 0
    init(responder: @escaping @Sendable ([UInt8]) -> [UInt8]?) { mock = MockHIDPPTransport(responder: responder) }
    var sentFrames: [[UInt8]] { mock.sentFrames }
    var closeCount: Int { lock.withLock { closes } }
    func send(_ bytes: [UInt8]) throws { try mock.send(bytes) }
    func setReportHandler(_ handler: @escaping @Sendable ([UInt8]) -> Void) { mock.setReportHandler(handler) }
    func close() { lock.withLock { closes += 1 } }
}

private final class InspectionFixtureOpener: @unchecked Sendable {
    let channel: InspectionFixtureChannel
    private let lock = NSLock()
    private var opens = 0
    private let openError: (any Error)?
    init(openError: (any Error)? = nil,
         responder: @escaping @Sendable ([UInt8]) -> [UInt8]? = inspectionFixtureReply) {
        self.openError = openError
        channel = InspectionFixtureChannel(responder: responder)
    }
    var openCount: Int { lock.withLock { opens } }
    func open() throws -> any CapabilityInspectionChannel {
        lock.withLock { opens += 1 }
        if let openError { throw openError }
        return channel
    }
}
