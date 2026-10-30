import Foundation

/// The onboard memory model of the Superstrike (feature 0x8100).
public struct OnboardInfo: Sendable, Equatable {
    public var memoryModel: UInt8
    public var profileFormat: UInt8
    public var macroEnabled: UInt8
    public var profileCount: Int
    public var outOfBounds: UInt8
    public var buttonCount: Int
    public var sectorCount: Int
    /// Bytes per profile sector (255 on the Superstrike).
    public var sectorSize: Int
    public var shift: UInt8
    /// The raw reply of fn0, kept for the diagnostics.
    public var raw: [UInt8]

    /// The Superstrike uses memory model 1.
    public var isSupportedModel: Bool { memoryModel == 0x01 }

    public init(
        memoryModel: UInt8,
        profileFormat: UInt8,
        macroEnabled: UInt8,
        profileCount: Int,
        outOfBounds: UInt8,
        buttonCount: Int,
        sectorCount: Int,
        sectorSize: Int,
        shift: UInt8,
        raw: [UInt8]
    ) {
        self.memoryModel = memoryModel
        self.profileFormat = profileFormat
        self.macroEnabled = macroEnabled
        self.profileCount = profileCount
        self.outOfBounds = outOfBounds
        self.buttonCount = buttonCount
        self.sectorCount = sectorCount
        self.sectorSize = sectorSize
        self.shift = shift
        self.raw = raw
    }
}

/// Result of writing a profile sector.
public enum SectorWriteOutcome: Sendable, Equatable {
    /// The sector was read back and matched byte for byte.
    case verified
    /// The write could not be confirmed. The device content is unknown — it has
    /// to be read again, never retried blindly.
    case uncertain(String)
    case uncertainReason(SuperstrikeFailure)
    /// The write never reached the device.
    case failedBeforeBegin(String)
    case failedBeforeBeginReason(SuperstrikeFailure)
}

/// Reads and writes the Superstrike's onboard profile memory (feature 0x8100).
public struct OnboardProfilesClient: Sendable {
    public let client: HIDPPClient
    public let feature: HIDPPFeature

    public init(client: HIDPPClient, feature: HIDPPFeature) {
        self.client = client
        self.feature = feature
    }

    /// Resolves the onboard profiles feature of a device.
    public static func resolve(for client: HIDPPClient) async throws -> OnboardProfilesClient? {
        guard let feature = try await client.resolveFeature(HIDPPFeatureID.onboardProfiles) else { return nil }
        return OnboardProfilesClient(client: client, feature: feature)
    }

    /// Reads the memory model (fn0).
    public func readInfo() async throws -> OnboardInfo {
        let data = try await client.request(featureIndex: feature.index, function: 0, shortFallback: true)
        guard data.count >= 9 else {
            throw HIDPPError.malformedReport("onboard info answered \(data.count) bytes")
        }
        return OnboardInfo(
            memoryModel: data[0],
            profileFormat: data[1],
            macroEnabled: data[2],
            profileCount: Int(data[3]),
            outOfBounds: data[4],
            buttonCount: Int(data[5]),
            sectorCount: Int(data[6]),
            sectorSize: (Int(data[7]) << 8) | Int(data[8]),
            shift: data.count >= 10 ? data[9] : 0,
            raw: data
        )
    }

    /// Reads the control mode (fn2): 1 = onboard, 2 = host.
    public func readMode() async throws -> Int {
        let data = try await client.request(featureIndex: feature.index, function: 2, shortFallback: true)
        guard let value = data.first else {
            throw HIDPPError.malformedReport("onboard mode answered \(data.count) bytes")
        }
        return Int(value)
    }

    /// The actual selected DPI stage (format 8), independent of its default.
    public func readActiveResolution() async throws -> Int {
        let data = try await client.request(featureIndex: feature.index, function: 0x0B, shortFallback: true)
        guard let index = data.first, index < 5 else {
            throw HIDPPError.malformedReport("invalid active DPI stage")
        }
        return Int(index)
    }

    /// Switches the control mode (fn1). Only ever called from an explicit user action.
    public func setMode(_ mode: Int) async throws {
        guard mode == 1 || mode == 2 else {
            throw HIDPPError.localized(key: "error.profile.invalidMode", arguments: [])
        }
        _ = try await client.request(featureIndex: feature.index, function: 1, payload: [UInt8(mode)])
    }

    /// Reads the sector the device is currently running (fn4).
    public func readCurrentSector() async throws -> Int {
        let data = try await client.request(featureIndex: feature.index, function: 4, shortFallback: true)
        guard data.count >= 2 else {
            throw HIDPPError.malformedReport("current profile answered \(data.count) bytes")
        }
        return (Int(data[0]) << 8) | Int(data[1])
    }

    /// Selects the running profile (fn3). Only ever called from an explicit user action.
    public func setCurrentProfile(_ sector: Int) async throws {
        _ = try await client.request(
            featureIndex: feature.index,
            function: 3,
            payload: [UInt8(truncatingIfNeeded: sector >> 8), UInt8(truncatingIfNeeded: sector)]
        )
    }

    /// Reads a full sector.
    ///
    /// The device rejects reads that run past the sector, so for a size that is not
    /// a multiple of 16 the last read is aligned to `size - 16` and only its tail
    /// is kept.
    public func readSector(_ sector: Int, size: Int) async throws -> [UInt8] {
        var content: [UInt8] = []
        content.reserveCapacity(size)
        var offset = 0
        while offset + 16 <= size {
            content.append(contentsOf: try await readChunk(sector: sector, offset: offset))
            offset += 16
        }
        if offset < size {
            let tail = try await readChunk(sector: sector, offset: size - 16)
            content.append(contentsOf: tail[(16 - (size - offset))...])
        }
        return Array(content.prefix(size))
    }

    /// Reads one 16 byte chunk of a sector (fn5).
    public func readChunk(sector: Int, offset: Int) async throws -> [UInt8] {
        let data = try await client.request(
            featureIndex: feature.index,
            function: 5,
            payload: [
                UInt8(truncatingIfNeeded: sector >> 8),
                UInt8(truncatingIfNeeded: sector),
                UInt8(truncatingIfNeeded: offset >> 8),
                UInt8(truncatingIfNeeded: offset),
            ],
            shortFallback: true
        )
        guard data.count >= 16 else {
            throw HIDPPError.malformedReport("sector chunk answered \(data.count) bytes")
        }
        return Array(data.prefix(16))
    }

    /// Reads the profile headers of the control sector.
    ///
    /// The control sector holds one four byte entry per profile slot
    /// `[sector, enabled, padding]`, terminated by `0xFFFF`. When the RAM control
    /// sector is blank the ROM control sector (0x0100) is used instead.
    public func readProfileHeaders() async throws -> [(sector: Int, enabled: Bool)] {
        let info = try await readInfo()
        var page = 0
        guard let first = try? await readChunk(sector: 0, offset: 0), first.count >= 4 else { return [] }
        var raw = first
        if first.prefix(4).allSatisfy({ $0 == 0x00 }) || first.prefix(4).allSatisfy({ $0 == 0xFF }) {
            page = 0x0100
            guard let romFirst = try? await readChunk(sector: page, offset: 0) else { return [] }
            raw = romFirst
        }
        var offset = 16
        while offset < 64 {
            guard let chunk = try? await readChunk(sector: page, offset: offset) else { break }
            raw.append(contentsOf: chunk)
            offset += 16
        }
        var headers: [(sector: Int, enabled: Bool)] = []
        var index = 0
        while index + 2 < raw.count, headers.count < max(1, info.profileCount) {
            if raw[index] == 0xFF, raw[index + 1] == 0xFF { break }
            let sector = (Int(raw[index]) << 8) | Int(raw[index + 1])
            guard sector >= 1, sector <= max(1, info.profileCount) else { break }
            headers.append((sector, raw[index + 2] == 0x01))
            index += 4
        }
        return headers
    }

    /// The profile sector the device is running.
    ///
    /// In host mode the device does not name a running profile, so the first
    /// enabled slot of the control sector is used instead. `isRunningSlot` says
    /// which of the two happened.
    public func activeProfileSector() async throws -> (sector: Int, isRunningSlot: Bool) {
        let info = try await readInfo()
        let current = (try? await readCurrentSector()) ?? 0
        if current >= 1, current <= info.profileCount {
            return (current, true)
        }
        let headers = try await readProfileHeaders()
        if let enabled = headers.first(where: { $0.enabled }) {
            return (enabled.sector, false)
        }
        if let first = headers.first {
            return (first.sector, false)
        }
        throw HIDPPError.localized(key: "error.profile.noAvailable", arguments: [])
    }

    /// Writes a sector (fn6 begin, fn7 chunk, fn8 commit) and verifies it by
    /// reading it back.
    ///
    /// Everything that can go wrong after the begin has started is reported as
    /// `.uncertain`: the device content is then unknown and must be read again.
    public func writeSector(_ sector: Int, bytes: [UInt8]) async throws -> SectorWriteOutcome {
        guard bytes.count >= 2 else {
            throw HIDPPError.localized(key: "error.profile.sectorTooShort", arguments: [])
        }
        let length = bytes.count
        do {
            _ = try await client.request(
                featureIndex: feature.index,
                function: 6,
                payload: [
                    UInt8(truncatingIfNeeded: sector >> 8),
                    UInt8(truncatingIfNeeded: sector),
                    0x00,
                    0x00,
                    UInt8(truncatingIfNeeded: length >> 8),
                    UInt8(truncatingIfNeeded: length),
                ]
            )
        } catch let error as HIDPPError {
            if case .timeout = error { return .uncertainReason(.localized(key: "error.profile.beginTimeout", arguments: [])) }
            throw error
        }

        var offset = 0
        while offset < length {
            let end = min(offset + 16, length)
            do {
                _ = try await client.request(
                    featureIndex: feature.index,
                    function: 7,
                    payload: Array(bytes[offset..<end])
                )
            } catch let error as HIDPPError {
                return .uncertainReason(.causedBy(key: "error.profile.chunkWriteFailed", arguments: [], cause: .hidpp(error)))
            }
            offset = end
        }

        do {
            _ = try await client.request(featureIndex: feature.index, function: 8)
        } catch let error as HIDPPError {
            return .uncertainReason(.causedBy(key: "error.profile.commitFailed", arguments: [], cause: .hidpp(error)))
        }

        guard let readBack = try? await readSector(sector, size: length) else {
            return .uncertainReason(.localized(key: "error.profile.readBackFailed", arguments: []))
        }
        return readBack == bytes
            ? .verified
            : .uncertainReason(.localized(key: "error.profile.readBackMismatch", arguments: []))
    }
}
