import Foundation

/// A HID++ request that has not been encoded yet.
///
/// The four byte header is: report identifier, device index, feature index and
/// (function ID << 4) | software ID. A successful reply carries the same header
/// and puts its parameters at byte 4 — there is no status byte.
public struct HIDPPRequest: Sendable {
    public var featureIndex: UInt8
    public var function: UInt8
    public var payload: [UInt8]
    /// Some devices only answer a function through a short report. When set, a timed out
    /// long report is retried once as a short report (reads only — never used for writes).
    public var shortFallback: Bool

    public init(featureIndex: UInt8, function: UInt8, payload: [UInt8] = [], shortFallback: Bool = false) {
        self.featureIndex = featureIndex
        self.function = function
        self.payload = payload
        self.shortFallback = shortFallback
    }

    /// Encodes the request. The report identifier is part of the wire format and is included.
    public func encoded(deviceIndex: UInt8, softwareID: UInt8, reportID: HIDPPReportID) throws -> [UInt8] {
        guard function <= 0x0F else {
            throw HIDPPError.unsupported("function \(function) does not fit the 4 bit function field")
        }
        guard (1...15).contains(softwareID) else {
            throw HIDPPError.unsupported("software ID \(softwareID) must be 1...15 for outgoing requests")
        }
        guard payload.count <= reportID.payloadLength else {
            throw HIDPPError.unsupported("payload \(payload.count) bytes does not fit a \(reportID) report")
        }
        var bytes: [UInt8] = [
            reportID.rawValue,
            deviceIndex,
            featureIndex,
            (function << 4) | (softwareID & 0x0F),
        ]
        bytes.append(contentsOf: payload)
        bytes.append(contentsOf: repeatElement(0, count: reportID.payloadLength - payload.count))
        return bytes
    }
}

/// A parsed HID++ reply.
public struct HIDPPResponse: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Parameters of a successful reply, starting at byte 4 of the frame.
        case success(data: [UInt8])
        /// Reason code (byte 5) of an error reply.
        case failure(reason: UInt8)
    }

    public var reportID: HIDPPReportID
    public var deviceIndex: UInt8
    /// Feature index of the request this reply answers.
    public var featureIndex: UInt8
    /// Function ID of the request this reply answers.
    public var function: UInt8
    /// Software ID of the request this reply answers (0 for a device notification).
    public var softwareID: UInt8
    public var outcome: Outcome

    public var data: [UInt8] {
        if case .success(let data) = outcome { return data }
        return []
    }

    public var reason: UInt8? {
        if case .failure(let reason) = outcome { return reason }
        return nil
    }

    public var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    public var isErrorReply: Bool { !isSuccess }

    /// Parses one complete frame (byte 0 is the report identifier).
    ///
    /// A frame must have the full length of its report type — 7 bytes for a short
    /// report, 20 bytes for a long one. Byte 2 holds an error marker (0x8F / 0xFF)
    /// for error replies; in that case byte 3 repeats the failed request's feature
    /// index, byte 4 its function and software ID, and byte 5 the reason code.
    public static func parse(_ bytes: [UInt8]) throws -> HIDPPResponse {
        guard let first = bytes.first, let reportID = HIDPPReportID(rawValue: first) else {
            throw HIDPPError.malformedReport("unknown report identifier")
        }
        guard bytes.count == reportID.reportLength else {
            throw HIDPPError.malformedReport(
                "a \(reportID) frame must be \(reportID.reportLength) bytes, got \(bytes.count)"
            )
        }
        let deviceIndex = bytes[1]
        let slot = bytes[2]
        if let marker = HIDPPErrorMarker(rawValue: slot) {
            _ = marker
            guard bytes.count >= 6 else {
                throw HIDPPError.malformedReport("error reply without a reason code")
            }
            let functionAndSoftware = bytes[4]
            return HIDPPResponse(
                reportID: reportID,
                deviceIndex: deviceIndex,
                featureIndex: bytes[3],
                function: functionAndSoftware >> 4,
                softwareID: functionAndSoftware & 0x0F,
                outcome: .failure(reason: bytes[5])
            )
        }
        let functionAndSoftware = bytes[3]
        return HIDPPResponse(
            reportID: reportID,
            deviceIndex: deviceIndex,
            featureIndex: slot,
            function: functionAndSoftware >> 4,
            softwareID: functionAndSoftware & 0x0F,
            outcome: .success(data: Array(bytes.dropFirst(4)))
        )
    }
}

/// Correlation key for a pending transaction.
///
/// A reply echoes bytes 1...3 of its request, so the device index, the feature
/// index, the function ID and the software ID all take part in the match.
struct HIDPPResponseKey: Hashable {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let function: UInt8
    let softwareID: UInt8
}
