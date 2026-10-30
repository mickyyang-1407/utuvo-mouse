import Foundation

/// Registry metadata only. Constructing this value neither opens nor probes a device.
/// Deliberately excludes names, unit IDs, serials, addresses and stable identifiers.
public struct CapabilityInspectionIdentity: Sendable, Equatable {
    public let vendorID: Int
    public let productID: Int
    public let transport: DeviceTransportKind

    public init(vendorID: Int, productID: Int, transport: DeviceTransportKind) {
        self.vendorID = vendorID
        self.productID = productID
        self.transport = transport
    }
}

/// An inspection owns its channel and always closes it, including on failure.
/// The opener must bind the channel to the identity it supplies to the collector.
public protocol CapabilityInspectionChannel: HIDPPTransport {
    func close()
}

/// Fixed diagnostic codes prevent transport errors from exposing device metadata.
public enum CapabilityInspectionError: String, Error, Sendable, Equatable {
    case consentRequired
    case identityMismatch
    case invalidArguments
    case invalidTimeout
    case unavailable
    case ambiguousDevice
    case accessDenied
    case transportFailure
    case timeout
    case malformedReply
    case unsupportedProtocol
    case featureSetUnavailable
    case featureLimitExceeded
    case deviceRejected
    case cancelled
}

/// An allowlisted output schema, separate from DeviceSnapshot and support requests.
/// A successful inspection grants no configuration support or physical verification.
public struct CapabilityInspectionReport: Sendable, Equatable, Encodable {
    public struct ProtocolVersion: Sendable, Equatable, Encodable {
        public let major: UInt8
        public let minor: UInt8
    }

    public let schemaVersion = 1
    public let modelKey = MXAnywhere3CapabilityInspection.modelKey
    public let vendorID = MXAnywhere3CapabilityInspection.vendorID
    public let productID = MXAnywhere3CapabilityInspection.productID
    public let transport = "bluetooth"
    public let readOnly = true
    public let configurationWritesEnabled = false
    public let protocolVersion: ProtocolVersion
    /// Four-digit IDs, including ROOT; never raw frames, runtime indexes or settings.
    public let featureIDs: [String]
}

/// Pure CLI routing, shared with fixture tests. Any inspection intent is consumed
/// before the executable can initialize its normal app or its broader --probe path.
public enum CapabilityInspectionInvocation: Sendable, Equatable {
    case notRequested
    case help
    case inspect

    public static let command = "--inspect-capabilities"
    public static let consent = "--allow-read-only-hidpp"

    public static func parse(_ arguments: [String]) throws -> Self {
        let requested = arguments.contains {
            $0 == command || $0.hasPrefix(command + "=")
                || $0 == consent || $0.hasPrefix(consent + "=")
        }
        guard requested else { return .notRequested }
        if arguments == [command, "--help"] || arguments == [command, "-h"] { return .help }
        guard arguments.contains(consent) else { throw CapabilityInspectionError.consentRequired }
        guard arguments == [command, MXAnywhere3CapabilityInspection.modelKey, consent] else {
            throw CapabilityInspectionError.invalidArguments
        }
        return .inspect
    }
}

/// Opt-in support foundation for exactly 046D:B025 over Bluetooth. This is kept
/// out of MouseModel and TargetProducts.allowed so automatic inventory stays passive.
/// Only ROOT getProtocolVersion/getFeature and FEATURE_SET getCount/getFeatureID
/// are called. Protocol facts and physical limitations: SUPPORT-CANDIDATE.md.
public enum MXAnywhere3CapabilityInspection {
    public static let modelKey = "046d-b025-bluetooth"
    public static let vendorID = 0x046D
    public static let productID = 0xB025
    public static let maximumFeatureCount = 64 // excludes ROOT
    public static let maximumRequestCount = maximumFeatureCount + 3
    public static let maximumReplyWait: Duration = .milliseconds(400)

    public static func validate(identity: CapabilityInspectionIdentity, consent: Bool) throws {
        guard consent else { throw CapabilityInspectionError.consentRequired }
        guard identity.vendorID == vendorID, identity.productID == productID,
              identity.transport == .bluetooth else { throw CapabilityInspectionError.identityMismatch }
    }

    /// Validation precedes even invoking the opener. No retries, fallback reads,
    /// partial-success reports, saved state or research-seeded feature defaults.
    public static func collect(
        identity: CapabilityInspectionIdentity,
        consent: Bool,
        replyTimeout: Duration = maximumReplyWait,
        openChannel: @Sendable () throws -> any CapabilityInspectionChannel
    ) async throws -> CapabilityInspectionReport {
        try validate(identity: identity, consent: consent)
        guard replyTimeout > .zero, replyTimeout <= maximumReplyWait else {
            throw CapabilityInspectionError.invalidTimeout
        }
        do {
            try Task.checkCancellation()
            let channel = try openChannel()
            defer { channel.close() }
            let client = try HIDPPClient(transport: channel, deviceIndex: 0xFF, timeout: replyTimeout)
            let mark = UInt8.random(in: 1...255)
            let version = try await read(client, featureIndex: 0, function: 1, payload: [0, 0, mark])
            guard version[2] == mark, version[1] <= 9 else {
                throw CapabilityInspectionError.malformedReply
            }
            guard version[0] == 2 || version[0] == 4 else { throw CapabilityInspectionError.unsupportedProtocol }

            let featureSet = try await read(client, featureIndex: 0, function: 0, payload: [0, 1])
            let setIndex = featureSet[0]
            guard setIndex != 0 else { throw CapabilityInspectionError.featureSetUnavailable }
            guard Int(setIndex) <= maximumFeatureCount else { throw CapabilityInspectionError.malformedReply }
            let countReply = try await read(client, featureIndex: setIndex, function: 0)
            let count = Int(countReply[0])
            guard count <= maximumFeatureCount else { throw CapabilityInspectionError.featureLimitExceeded }
            guard count > 0, Int(setIndex) <= count else { throw CapabilityInspectionError.malformedReply }

            // GetCount excludes ROOT. All indexes 1...count must return unique
            // IDs and agree with ROOT's FEATURE_SET index before any report exists.
            var ids: Set<UInt16> = [HIDPPFeatureID.root]
            for index in 1...count {
                let data = try await read(client, featureIndex: setIndex, function: 1, payload: [UInt8(index)])
                let id = (UInt16(data[0]) << 8) | UInt16(data[1])
                guard ids.insert(id).inserted,
                      (id == HIDPPFeatureID.featureSet) == (index == Int(setIndex)) else {
                    throw CapabilityInspectionError.malformedReply
                }
            }
            return CapabilityInspectionReport(
                protocolVersion: .init(major: version[0], minor: version[1]),
                featureIDs: ids.sorted().map { String(format: "%04X", $0) }
            )
        } catch let error as CapabilityInspectionError {
            throw error
        } catch is CancellationError {
            throw CapabilityInspectionError.cancelled
        } catch let error as HIDPPError {
            switch error {
            case .timeout: throw CapabilityInspectionError.timeout
            case .malformedReport: throw CapabilityInspectionError.malformedReply
            case .deviceError: throw CapabilityInspectionError.deviceRejected
            default: throw CapabilityInspectionError.transportFailure
            }
        } catch {
            throw CapabilityInspectionError.transportFailure
        }
    }

    private static func read(
        _ client: HIDPPClient, featureIndex: UInt8, function: UInt8, payload: [UInt8] = []
    ) async throws -> [UInt8] {
        try Task.checkCancellation()
        let data = try await client.request(featureIndex: featureIndex, function: function, payload: payload)
        // HIDPPClient validates complete 7/20-byte frames and full correlation.
        guard data.count >= 3 else { throw CapabilityInspectionError.malformedReply }
        try Task.checkCancellation()
        return data
    }
}
