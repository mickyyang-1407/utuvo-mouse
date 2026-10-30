import Foundation
import CryptoKit
import UTUVOMouseCore

/// Where a stored capability record came from.
///
/// `imported` records are file-supplied observations. They are never
/// device-confirmed, never physically verified and never a release.
public enum CapabilityRecordOrigin: String, Codable, Sendable, Equatable {
    /// Collected by the app itself through the read-only inspection service.
    case appReadOnly
    /// Supplied from a file. Always a developer handoff, never a device fact.
    case imported
}

/// Fixed failure codes. They never carry the offending value, the file name or
/// any other input, so a failure message cannot leak device or user data.
public enum CapabilityRecordError: String, Error, Sendable, Equatable {
    case tooLarge
    case malformed
    case unexpectedField
    case typeMismatch
    case identityMismatch
    case unsupportedProtocol
    case invalidFeatureIDs
    case readOnlyRequired
    case configurationWritesForbidden
    case invalidOrigin
    /// A stored record claimed hardware behaviour or a release.
    case forbiddenClaim
}

/// The allowlisted subset of an inspection report.
///
/// Safe schema only: model identity, protocol version and feature IDs. It
/// carries no name, serial, unit ID, address, timestamp, local path, setting
/// or raw frame, and it can never enable a configuration write.
public struct CapabilityReport: Encodable, Equatable, Sendable {
    public struct ProtocolVersion: Encodable, Equatable, Sendable {
        public let major: Int
        public let minor: Int
    }

    public let schemaVersion: Int
    public let modelKey: String
    public let vendorID: Int
    public let productID: Int
    public let transport: String
    public let readOnly: Bool
    public let configurationWritesEnabled: Bool
    public let protocolVersion: ProtocolVersion
    /// Four-digit uppercase IDs, including ROOT. No raw frames or indexes.
    public let featureIDs: [String]

    public init(
        schemaVersion: Int,
        modelKey: String,
        vendorID: Int,
        productID: Int,
        transport: String,
        readOnly: Bool,
        configurationWritesEnabled: Bool,
        protocolVersion: ProtocolVersion,
        featureIDs: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.modelKey = modelKey
        self.vendorID = vendorID
        self.productID = productID
        self.transport = transport
        self.readOnly = readOnly
        self.configurationWritesEnabled = configurationWritesEnabled
        self.protocolVersion = protocolVersion
        self.featureIDs = featureIDs
    }

    /// Normalizes an app-collected inspection report into the safe schema.
    public init(report: CapabilityInspectionReport) {
        self.init(
            schemaVersion: report.schemaVersion,
            modelKey: report.modelKey,
            vendorID: report.vendorID,
            productID: report.productID,
            transport: report.transport,
            readOnly: report.readOnly,
            configurationWritesEnabled: report.configurationWritesEnabled,
            protocolVersion: .init(
                major: Int(report.protocolVersion.major),
                minor: Int(report.protocolVersion.minor)
            ),
            featureIDs: report.featureIDs
        )
    }
}

/// A stored capability record.
///
/// The envelope has exactly five fields. `hardwareBehaviorVerified` and
/// `released` are structurally false: no file, import, mock or program test can
/// turn them true.
public struct CapabilityRecord: Encodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let origin: CapabilityRecordOrigin
    public let report: CapabilityReport
    public let hardwareBehaviorVerified: Bool
    public let released: Bool

    public init(origin: CapabilityRecordOrigin, report: CapabilityReport) {
        schemaVersion = 1
        self.origin = origin
        self.report = report
        hardwareBehaviorVerified = false
        released = false
    }

    /// The fingerprint of this exact input revision.
    public var fingerprint: String {
        CapabilityFingerprint.sha256Hex(
            CapabilityFingerprint.canonical(
                modelKey: report.modelKey,
                origin: origin,
                major: report.protocolVersion.major,
                minor: report.protocolVersion.minor,
                featureIDs: report.featureIDs
            )
        )
    }
}

/// The one canonical fingerprint recipe shared by Swift and the Python worker.
///
/// Canonical string, no trailing newline:
/// `v1` LF `modelKey` LF `origin` LF `major.minor` LF `featureIDs` joined by `,`
/// The SHA-256 of its UTF-8 bytes is the fingerprint.
public enum CapabilityFingerprint {
    public static let version = "v1"

    public static func canonical(
        modelKey: String,
        origin: CapabilityRecordOrigin,
        major: Int,
        minor: Int,
        featureIDs: [String]
    ) -> String {
        [
            version,
            modelKey,
            origin.rawValue,
            "\(major).\(minor)",
            featureIDs.sorted().joined(separator: ",")
        ].joined(separator: "\n")
    }

    public static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Strict reader for capability JSON.
///
/// Every value is checked by exact type. A JSON boolean never passes as an
/// integer, a JSON number never passes as a boolean, and any key outside the
/// allowlist is a failure instead of being ignored.
enum CapabilityJSON {
    enum Failure: Error {
        case malformed
        case unexpectedField
        case typeMismatch
    }

    static func parseObject(_ data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else { throw Failure.malformed }
        return object
    }

    static func isBoolean(_ any: Any) -> Bool {
        CFGetTypeID(any as CFTypeRef) == CFBooleanGetTypeID()
    }

    static func integer(_ any: Any) throws -> Int {
        guard let number = any as? NSNumber, !isBoolean(any) else { throw Failure.typeMismatch }
        guard CFNumberIsFloatType(number as CFNumber) == false else { throw Failure.typeMismatch }
        let value = number.intValue
        guard Double(value) == number.doubleValue else { throw Failure.typeMismatch }
        return value
    }

    static func boolean(_ any: Any) throws -> Bool {
        guard isBoolean(any) else { throw Failure.typeMismatch }
        return (any as! NSNumber).boolValue
    }

    static func string(_ any: Any) throws -> String {
        guard let value = any as? String else { throw Failure.typeMismatch }
        return value
    }

    static func object(_ any: Any) throws -> [String: Any] {
        guard let value = any as? [String: Any] else { throw Failure.typeMismatch }
        return value
    }

    static func array(_ any: Any) throws -> [Any] {
        guard let value = any as? [Any] else { throw Failure.typeMismatch }
        return value
    }
}

/// The pure Support-layer validator and codec for capability records.
///
/// It consumes the existing `CapabilityInspectionReport` JSON and produces a
/// normalized envelope. It never touches hardware, never writes a device
/// setting and never grants configuration support.
public enum CapabilityRecordCodec {
    /// Largest accepted report payload.
    public static let maximumReportByteCount = 16 * 1024
    /// Largest accepted stored envelope. It only adds the five envelope keys.
    public static let maximumRecordByteCount = 64 * 1024

    static let reportKeys: Set<String> = [
        "schemaVersion", "modelKey", "vendorID", "productID", "transport",
        "readOnly", "configurationWritesEnabled", "protocolVersion", "featureIDs"
    ]
    static let envelopeKeys: Set<String> = [
        "schemaVersion", "origin", "report", "hardwareBehaviorVerified", "released"
    ]
    static let protocolVersionKeys: Set<String> = ["major", "minor"]

    /// Strictly decodes an inspection report payload.
    public static func decodeReport(from data: Data) throws -> CapabilityReport {
        guard data.count <= maximumReportByteCount else { throw CapabilityRecordError.tooLarge }
        let root: [String: Any]
        do { root = try CapabilityJSON.parseObject(data) }
        catch { throw CapabilityRecordError.malformed }
        guard reportKeys.isSuperset(of: Set(root.keys)) else {
            throw CapabilityRecordError.unexpectedField
        }
        for key in reportKeys where root[key] == nil {
            throw CapabilityRecordError.malformed
        }
        guard root.keys.count == reportKeys.count else { throw CapabilityRecordError.unexpectedField }

        let schemaVersion = try integer(root["schemaVersion"]!)
        guard schemaVersion == 1 else { throw CapabilityRecordError.malformed }
        let modelKey = try string(root["modelKey"]!)
        let vendorID = try integer(root["vendorID"]!)
        let productID = try integer(root["productID"]!)
        let transport = try string(root["transport"]!)
        guard modelKey == MXAnywhere3CapabilityInspection.modelKey,
              vendorID == MXAnywhere3CapabilityInspection.vendorID,
              productID == MXAnywhere3CapabilityInspection.productID,
              transport == "bluetooth" else { throw CapabilityRecordError.identityMismatch }

        let readOnly = try boolean(root["readOnly"]!)
        guard readOnly else { throw CapabilityRecordError.readOnlyRequired }
        let configurationWritesEnabled = try boolean(root["configurationWritesEnabled"]!)
        guard !configurationWritesEnabled else { throw CapabilityRecordError.configurationWritesForbidden }

        let version = try CapabilityJSON.object(root["protocolVersion"]!)
        guard protocolVersionKeys.isSuperset(of: Set(version.keys)),
              version.keys.count == protocolVersionKeys.count else {
            throw CapabilityRecordError.unexpectedField
        }
        for key in protocolVersionKeys where version[key] == nil {
            throw CapabilityRecordError.malformed
        }
        let major = try integer(version["major"]!)
        let minor = try integer(version["minor"]!)
        guard major == 2 || major == 4 else { throw CapabilityRecordError.unsupportedProtocol }
        guard minor >= 0, minor <= 9 else { throw CapabilityRecordError.unsupportedProtocol }

        let featureIDs = try CapabilityJSON.array(root["featureIDs"]!).map { try string($0) }
        try validateFeatureIDs(featureIDs)

        return CapabilityReport(
            schemaVersion: schemaVersion,
            modelKey: modelKey,
            vendorID: vendorID,
            productID: productID,
            transport: transport,
            readOnly: readOnly,
            configurationWritesEnabled: configurationWritesEnabled,
            protocolVersion: .init(major: major, minor: minor),
            featureIDs: featureIDs
        )
    }

    /// Strictly decodes a stored envelope. A stored record can never claim
    /// hardware behaviour or a release, and never enable configuration writes.
    public static func decodeRecord(from data: Data) throws -> CapabilityRecord {
        guard data.count <= maximumRecordByteCount else { throw CapabilityRecordError.tooLarge }
        let root: [String: Any]
        do { root = try CapabilityJSON.parseObject(data) }
        catch { throw CapabilityRecordError.malformed }
        guard envelopeKeys.isSuperset(of: Set(root.keys)) else {
            throw CapabilityRecordError.unexpectedField
        }
        for key in envelopeKeys where root[key] == nil {
            throw CapabilityRecordError.malformed
        }
        guard root.keys.count == envelopeKeys.count else { throw CapabilityRecordError.unexpectedField }

        guard try integer(root["schemaVersion"]!) == 1 else { throw CapabilityRecordError.malformed }
        let originRaw = try string(root["origin"]!)
        guard let origin = CapabilityRecordOrigin(rawValue: originRaw) else {
            throw CapabilityRecordError.invalidOrigin
        }
        let verified = try boolean(root["hardwareBehaviorVerified"]!)
        let released = try boolean(root["released"]!)
        guard !verified, !released else { throw CapabilityRecordError.forbiddenClaim }

        let reportData = try CapabilityJSON.object(root["report"]!)
        let report = try decodeReportObject(reportData)
        return CapabilityRecord(origin: origin, report: report)
    }

    /// Builds a record from an app-collected report.
    public static func makeRecord(inspection: CapabilityInspectionReport, origin: CapabilityRecordOrigin) throws -> CapabilityRecord {
        let record = CapabilityRecord(origin: origin, report: CapabilityReport(report: inspection))
        try validateReportValues(record.report)
        return record
    }

    /// Builds a record from a validated report.
    public static func makeRecord(report: CapabilityReport, origin: CapabilityRecordOrigin) throws -> CapabilityRecord {
        try validateReportValues(report)
        return CapabilityRecord(origin: origin, report: report)
    }

    /// Builds a record from a report payload. The origin is always explicit:
    /// an imported payload is never device-confirmed.
    public static func makeRecord(reportPayload data: Data, origin: CapabilityRecordOrigin) throws -> CapabilityRecord {
        let report = try decodeReport(from: data)
        return try makeRecord(report: report, origin: origin)
    }

    /// Encodes a record for storage. The output holds no timestamp, name,
    /// serial, address, local path, setting or raw frame.
    ///
    /// The report is validated first: a record that was built by hand and
    /// never validated can never be encoded, and therefore never be stored.
    public static func encode(_ record: CapabilityRecord) throws -> Data {
        try validateReportValues(record.report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(record)
    }

    /// Re-validates an already decoded report.
    public static func validateReportValues(_ report: CapabilityReport) throws {
        guard report.schemaVersion == 1 else { throw CapabilityRecordError.malformed }
        guard report.modelKey == MXAnywhere3CapabilityInspection.modelKey,
              report.vendorID == MXAnywhere3CapabilityInspection.vendorID,
              report.productID == MXAnywhere3CapabilityInspection.productID,
              report.transport == "bluetooth" else { throw CapabilityRecordError.identityMismatch }
        guard report.readOnly else { throw CapabilityRecordError.readOnlyRequired }
        guard !report.configurationWritesEnabled else { throw CapabilityRecordError.configurationWritesForbidden }
        guard report.protocolVersion.major == 2 || report.protocolVersion.major == 4,
              report.protocolVersion.minor >= 0, report.protocolVersion.minor <= 9 else {
            throw CapabilityRecordError.unsupportedProtocol
        }
        try validateFeatureIDs(report.featureIDs)
    }

    static func validateFeatureIDs(_ featureIDs: [String]) throws {
        guard !featureIDs.isEmpty,
              featureIDs.count <= MXAnywhere3CapabilityInspection.maximumFeatureCount + 1 else {
            throw CapabilityRecordError.invalidFeatureIDs
        }
        var previous = ""
        for id in featureIDs {
            guard id.count == 4, id.allSatisfy({ hexDigits.contains($0) }) else {
                throw CapabilityRecordError.invalidFeatureIDs
            }
            guard id > previous else { throw CapabilityRecordError.invalidFeatureIDs } // sorted and unique
            previous = id
        }
        // ROOT and FEATURE_SET must both be present; a report without them is
        // not a complete inspection.
        guard featureIDs.contains(rootFeatureID), featureIDs.contains(featureSetFeatureID) else {
            throw CapabilityRecordError.invalidFeatureIDs
        }
    }

    /// Exactly the ASCII uppercase hex digits. No Unicode look-alikes.
    static let hexDigits = Set("0123456789ABCDEF")

    static let rootFeatureID = String(format: "%04X", HIDPPFeatureID.root)
    static let featureSetFeatureID = String(format: "%04X", HIDPPFeatureID.featureSet)

    // MARK: - Helpers

    private static func decodeReportObject(_ object: [String: Any]) throws -> CapabilityReport {
        guard reportKeys.isSuperset(of: Set(object.keys)) else {
            throw CapabilityRecordError.unexpectedField
        }
        for key in reportKeys where object[key] == nil {
            throw CapabilityRecordError.malformed
        }
        guard object.keys.count == reportKeys.count else { throw CapabilityRecordError.unexpectedField }

        let schemaVersion = try integer(object["schemaVersion"]!)
        guard schemaVersion == 1 else { throw CapabilityRecordError.malformed }
        let modelKey = try string(object["modelKey"]!)
        let vendorID = try integer(object["vendorID"]!)
        let productID = try integer(object["productID"]!)
        let transport = try string(object["transport"]!)
        guard modelKey == MXAnywhere3CapabilityInspection.modelKey,
              vendorID == MXAnywhere3CapabilityInspection.vendorID,
              productID == MXAnywhere3CapabilityInspection.productID,
              transport == "bluetooth" else { throw CapabilityRecordError.identityMismatch }
        let readOnly = try boolean(object["readOnly"]!)
        guard readOnly else { throw CapabilityRecordError.readOnlyRequired }
        let configurationWritesEnabled = try boolean(object["configurationWritesEnabled"]!)
        guard !configurationWritesEnabled else { throw CapabilityRecordError.configurationWritesForbidden }
        let version = try CapabilityJSON.object(object["protocolVersion"]!)
        guard protocolVersionKeys.isSuperset(of: Set(version.keys)),
              version.keys.count == protocolVersionKeys.count else {
            throw CapabilityRecordError.unexpectedField
        }
        for key in protocolVersionKeys where version[key] == nil {
            throw CapabilityRecordError.malformed
        }
        let major = try integer(version["major"]!)
        let minor = try integer(version["minor"]!)
        guard major == 2 || major == 4 else { throw CapabilityRecordError.unsupportedProtocol }
        guard minor >= 0, minor <= 9 else { throw CapabilityRecordError.unsupportedProtocol }
        let featureIDs = try CapabilityJSON.array(object["featureIDs"]!).map { try string($0) }
        try validateFeatureIDs(featureIDs)
        return CapabilityReport(
            schemaVersion: schemaVersion,
            modelKey: modelKey,
            vendorID: vendorID,
            productID: productID,
            transport: transport,
            readOnly: readOnly,
            configurationWritesEnabled: configurationWritesEnabled,
            protocolVersion: .init(major: major, minor: minor),
            featureIDs: featureIDs
        )
    }

    private static func integer(_ any: Any) throws -> Int {
        do { return try CapabilityJSON.integer(any) }
        catch { throw CapabilityRecordError.typeMismatch }
    }

    private static func boolean(_ any: Any) throws -> Bool {
        do { return try CapabilityJSON.boolean(any) }
        catch { throw CapabilityRecordError.typeMismatch }
    }

    private static func string(_ any: Any) throws -> String {
        do { return try CapabilityJSON.string(any) }
        catch { throw CapabilityRecordError.typeMismatch }
    }
}
