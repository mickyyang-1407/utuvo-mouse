import Foundation
import Testing
@testable import UTUVOMouseCore

/// CRC, sector layout and the write path of the onboard profile.
@Suite("Superstrike profile")
struct SuperstrikeProfileTests {

    @Test("CRC-16/CCITT-FALSE matches the known vector")
    func crcKnownVector() {
        let bytes = Array("123456789".utf8)
        #expect(CRC16CCITT.compute(bytes) == 0x29B1)
    }

    @Test("a sector with a wrong CRC is rejected")
    func crcRejection() {
        var bytes = [UInt8](repeating: 0, count: 255)
        bytes[0] = 3
        bytes[9] = 0x00; bytes[10] = 0x0C  // 3200 LE
        let sector = ProfileSector(bytes: bytes, sector: 1).withRecomputedCRC()
        #expect(sector.hasValidCRC)
        var broken = sector
        broken.bytes[9] = 0x01
        #expect(!broken.hasValidCRC)
    }

    @Test("selected stage 1 lives at 4 + 1 * 5 and is little endian")
    func dpiOffsets() {
        var bytes = [UInt8](repeating: 0, count: 255)
        bytes[2] = 1
        bytes[9] = 0x80; bytes[10] = 0x0C   // X = 3200 (0x0C80) little endian
        bytes[11] = 0x00; bytes[12] = 0x14  // Y = 5120 (0x1400) little endian
        let sector = ProfileSector(bytes: bytes, sector: 1)
        #expect(sector.dpiX == 3200)
        #expect(sector.dpiY == 5120)
    }

    @Test("the report rate byte encodes 125 << byte")
    func reportRateEncoding() {
        #expect(ProfileLayout.reportRateHz(forByte: 0) == 125)
        #expect(ProfileLayout.reportRateHz(forByte: 3) == 1000)
        #expect(ProfileLayout.reportRateHz(forByte: 6) == 8000)
        #expect(ProfileLayout.reportRateByte(forHz: 4000) == 5)
        #expect(ProfileLayout.reportRateByte(forHz: 3000) == nil)
    }

    @Test("patching DPI keeps every other byte")
    func patchPreservesOtherBytes() throws {
        var bytes = [UInt8](repeating: 0x5A, count: 255)
        bytes[2] = 1
        let original = ProfileSector(bytes: bytes, sector: 1)
        let patched = try original.settingDPI(x: 1600, y: 800)
        let changed = zip(original.bytes, patched.bytes).enumerated().filter { $0.element.0 != $0.element.1 }.map { $0.offset }
        // Only the two DPI words and the two CRC bytes may differ.
        #expect(Set(changed).isSubset(of: [9, 10, 11, 12, 253, 254]))
    }

    @Test("patching a button slot keeps every other byte")
    func patchButtonPreservesOtherBytes() throws {
        var bytes = [UInt8](repeating: 0x11, count: 255)
        bytes[48] = 0x80; bytes[49] = 0x01; bytes[50] = 0x00; bytes[51] = 0x08
        let original = ProfileSector(bytes: bytes, sector: 1)
        let patched = try original.settingButton(slot: 3, action: ButtonAction(kind: .mouse, code: 0x0010))
        let changed = zip(original.bytes, patched.bytes).enumerated().filter { $0.element.0 != $0.element.1 }.map { $0.offset }
        // Slot 3 sits at 48 + 3 * 4 = 60, plus the two CRC bytes.
        #expect(Set(changed).isSubset(of: [60, 61, 62, 63, 253, 254]))
        #expect(patched.buttonSlots[3].kind == .mouse)
        #expect(patched.buttonSlots[3].code == 0x0010)
    }

    @Test("the button table starts at 48 and not at 32")
    func buttonTableOffset() {
        var bytes = [UInt8](repeating: 0xFF, count: 255)
        bytes[48] = 0x80; bytes[49] = 0x01; bytes[50] = 0x00; bytes[51] = 0x02
        let sector = ProfileSector(bytes: bytes, sector: 1)
        #expect(sector.buttonSlots[0].kind == .mouse)
        #expect(sector.buttonSlots[0].code == 0x0002)
        #expect(sector.buttonSlots[1].kind == .disabled)
    }
}

/// A backup store that always fails, to prove that no write happens without a backup.
private struct FailingBackupStore: BackupStoring {
    func store(_ backup: SectorBackup) throws -> URL {
        throw BackupError.unreadable(URL(fileURLWithPath: "/tmp/utuvo-mouse-must-not-exist"))
    }
}

/// A fake Superstrike that answers the onboard profile functions.
private final class FakeSuperstrike: @unchecked Sendable {
    enum Behavior: Sendable {
        case normal
        case timeoutOnCommit
        case corruptOnCommit
    }

    let lock = NSLock()
    var behavior: Behavior = .normal
    /// The control mode the device reports: 1 = onboard, 2 = host.
    var mode: UInt8 = 0x01
    var sector: [UInt8]
    var currentSector: UInt16 = 1
    var writeCount = 0
    var beginCount = 0
    var badGridHeader = false
    var liveHITSOverride: [[UInt8]]?
    var committed: [UInt8] = []
    private var pending: [UInt8] = []
    private var pendingLength = 0

    let featureIndexes: [UInt16: UInt8] = [
        0x0000: 0x00,
        0x1004: 0x01,
        0x1B0C: 0x02,
        0x2201: 0x03,
        0x2202: 0x09,
        0x8100: 0x0A,
    ]

    init(sector: [UInt8]) {
        self.sector = sector
    }

    func reply(to request: [UInt8]) -> [UInt8]? {
        lock.withLock {
            let deviceIndex = request[1]
            let feature = request[2]
            let function = request[3] >> 4
            let software = request[3] & 0x0F
            let payload = Array(request[4...])

            func frame(_ data: [UInt8]) -> [UInt8] {
                var bytes: [UInt8] = [0x11, deviceIndex, feature, (function << 4) | software]
                bytes.append(contentsOf: data)
                bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - data.count)))
                return bytes
            }

            switch feature {
            case 0x00:
                switch function {
                case 0x00:
                    let id = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    let index = featureIndexes[id] ?? 0
                    return frame([index, 0x00, 0x01])
                case 0x01:
                    return frame([0x04, 0x02])
                default:
                    return nil
                }
            case 0x09:
                if function == 2 {
                    let axis = badGridHeader ? payload[1] ^ 1 : payload[1]
                    return frame([0,axis,payload[2],0,100,0xE0,20,0xAB,0xE0,0,0])
                }
                let offset = 4 + Int(sector[2]) * 5
                return frame([0, sector[offset+1], sector[offset], sector[offset+1], sector[offset], sector[offset+3], sector[offset+2], sector[offset+3], sector[offset+2], sector[offset+4]])
            case 0x0A:  // OnboardProfiles
                switch function {
                case 0x00:  // getInfo
                    // The real Superstrike answers: 01 08 01 05 01 05 10 00 FF 0A …
                    return frame([0x01, 0x08, 0x01, 0x05, 0x01, 0x05, 0x10, 0x00, 0xFF, 0x0A])
                case 0x02:  // getMode
                    return frame([mode])
                case 0x0B: return frame([sector[2]])
                case 0x04:  // getCurrentProfile
                    return frame([UInt8(currentSector >> 8), UInt8(currentSector & 0xFF)])
                case 0x05:  // read
                    let requestedSector = (Int(payload[0]) << 8) | Int(payload[1])
                    let offset = (Int(payload[2]) << 8) | Int(payload[3])
                    // The control sector holds the profile table: one four byte
                    // entry per slot, [sector, enabled, padding].
                    if requestedSector == 0 {
                        var control = [UInt8](repeating: 0, count: 256)
                        control[0] = 0x00; control[1] = 0x01; control[2] = 0x01
                        control[4] = 0x00; control[5] = 0x02; control[6] = 0x01
                        guard offset + 16 <= control.count else { return nil }
                        return frame(Array(control[offset..<(offset + 16)]))
                    }
                    guard offset + 16 <= sector.count else { return nil }
                    return frame(Array(sector[offset..<(offset + 16)]))
                case 0x06:  // begin
                    beginCount += 1
                    pendingLength = (Int(payload[4]) << 8) | Int(payload[5])
                    pending = []
                    return frame([])
                case 0x07:  // write chunk
                    pending.append(contentsOf: payload)
                    return frame([])
                case 0x08:  // commit
                    writeCount += 1
                    if behavior == .timeoutOnCommit { return nil }
                    committed = Array(pending.prefix(pendingLength))
                    if behavior == .corruptOnCommit, !committed.isEmpty {
                        committed[committed.count - 1] ^= 0xFF
                    }
                    sector = committed
                    liveHITSOverride = nil
                    return frame([])
                default:
                    return nil
                }
            case 0x02:  // ANALOG_BUTTONS
                switch function {
                case 0x00:
                    return frame([0x00, 0x03, 10 << 2, 5 << 2, 5 << 2])
                case 0x02:
                    // [button, act<<2, rt<<2 | flag, haptics<<2]
                    let offset = 38 + Int(payload[0]) * 3
                    return frame([payload[0]] + (liveHITSOverride?[Int(payload[0])] ?? Array(sector[offset..<(offset+3)])))
                default:
                    return nil
                }
            default:
                return nil
            }
        }
    }
}

/// The write path: backup first, then write, then verify.
@Suite("Superstrike write path")
struct SuperstrikeWriteTests {
    private func applyDPI(_ service: SuperstrikeService, _ x: Int, _ y: Int, baseline: ProfileSector? = nil) async throws -> ApplyOutcome {
        let plan = try await service.readPlan()
        let current = baseline ?? ProfileSector(bytes: makeSector().bytes, sector: plan.storedSector)
        return await service.applyCompound(plan: plan, baseline: current, changes: CompoundChanges(dpiX: x, dpiY: y))
    }

    private func makeService(
        device: FakeSuperstrike,
        store: BackupStoring
    ) throws -> (SuperstrikeService, HIDPPClient) {
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let onboard = OnboardProfilesClient(
            client: client,
            feature: HIDPPFeature(id: 0x8100, index: 0x0A, version: 1)
        )
        let service = SuperstrikeService(client: client, onboard: onboard, backupStore: store, deviceID: "test-device")
        return (service, client)
    }

    private func makeSector() -> ProfileSector {
        var bytes = [UInt8](repeating: 0, count: 255)
        bytes[0] = 3            // 1000 Hz
        bytes.replaceSubrange(38..<44, with: [20,8,12,20,8,12])
        bytes[2] = 1
        bytes[9] = 0x80; bytes[10] = 0x0C  // X = 3200
        bytes[11] = 0x80; bytes[12] = 0x0C // Y = 3200
        return ProfileSector(bytes: bytes, sector: 1).withRecomputedCRC()
    }

    private func temporaryStore() -> (FileBackupStore, URL) {
        let root = MouseTestTemporaryRoot.url
            .appendingPathComponent("utuvo-mouse-tests-\(UUID().uuidString)")
        return (FileBackupStore(root: root), root)
    }

    @Test("persistent HITS is backed up, verified in NVM and applied live")
    func persistentHITSApplies() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, client) = try makeService(device: device, store: store)
        let plan = try await service.readPlan()
        let result = await service.applyCompound(plan: plan, baseline: makeSector(), changes: .init(hits: [.init(button: 0, rapidTrigger: 3)]))
        #expect(result.isApplied)
        #expect(device.sector[39] == 0x0D)
        #expect(Array(device.sector[41..<44]) == [20,8,12])
        let live = try await client.readHitsButton(0)
        #expect(live.rapidTriggerEnabled && live.rapidTrigger == 3)
        let after = ProfileSector(bytes: device.sector, sector: 1)
        let restored = await service.applyCompound(plan: plan, baseline: after, changes: .init(hits: [.init(button: 0, rapidTrigger: 0)]))
        #expect(restored.isApplied)
        #expect(device.sector[39] == 0x0C) // Disabled, sensitivity remains 3.
    }

    @Test("saving HITS reconciles volatile settings without resetting the other key or NVM reserved bits")
    func saveLiveHITSDrift() async throws {
        var original = makeSector()
        original.bytes.replaceSubrange(38..<44, with: [23,10,13,22,8,15])
        original = original.withRecomputedCRC()
        let device = FakeSuperstrike(sector: original.bytes)
        device.liveHITSOverride = [[24,13,16], [16,5,8]]
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let plan = try await service.readPlan()
        let result = await service.applyCompound(plan: plan, baseline: original, changes: .init(hits: [.init(button: 0, rapidTrigger: 0)]))
        #expect(result.isApplied)
        #expect(Array(device.sector[38..<44]) == [27,14,17,18,5,11])
        let changed = zip(original.bytes, device.sector).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        #expect(Set(changed).isSubset(of: [38,39,40,41,42,43,253,254]))
    }

    @Test("off-grid DPI is rejected before a flash begin or commit")
    func offGridNoWrite() async throws {
        let original = makeSector()
        let device = FakeSuperstrike(sector: original.bytes)
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let result = try await applyDPI(service, 3250, 3250)
        guard case .failedReason(.localized(let key, _)) = result else {
            Issue.record("unsupported DPI must fail before writing: \(result)"); return
        }
        #expect(key == "error.profile.dpiUnsupported")
        #expect(device.beginCount == 0 && device.writeCount == 0)
        #expect(device.sector == original.bytes)
    }

    @Test("valid DPI on the advertised grid is written and verified")
    func onGridDPI() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let result = try await applyDPI(service, 3300, 3300)
        #expect(result.isApplied)
        #expect(device.beginCount == 1 && device.writeCount == 1)
    }

    @Test("malformed grid echo refuses the write even for otherwise valid DPI")
    func badGridNoWrite() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        device.badGridHeader = true
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let result = try await applyDPI(service, 3300, 3300)
        #expect(!result.isApplied)
        #expect(device.beginCount == 0 && device.writeCount == 0)
    }

    @Test("host mode stops the write before any sector is touched")
    func hostModeWritesNothing() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        device.mode = 0x02
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let plan = try await service.readPlan()
        let outcome = await service.applyCompound(
            plan: plan,
            baseline: makeSector(),
            changes: CompoundChanges(dpiX: 1600, dpiY: 1600)
        )
        guard case .needsOnboardSelection = outcome else {
            Issue.record("expected needsOnboardSelection, got \(outcome)")
            return
        }
        // No begin, no chunk, no commit.
        #expect(device.writeCount == 0)
    }

    @Test("a failed backup stops the write")
    func backupFailureBlocksWrite() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        let (service, _) = try makeService(device: device, store: FailingBackupStore())
        let outcome = try await applyDPI(service, 1600, 1600)
        guard case .backupFailedReason(.backup(.unreadable(let fileURL))) = outcome else {
            Issue.record("expected a typed backup failure, got \(outcome)")
            return
        }
        #expect(fileURL.lastPathComponent == "utuvo-mouse-must-not-exist")
        #expect(outcome.localizedSummary(language: .english).contains("Backup failed"))
        #expect(outcome.localizedSummary(language: .english).contains("utuvo-mouse-must-not-exist"))
        #expect(device.writeCount == 0)
    }

    @Test("a changed device is rejected before anything is written")
    func staleBaselineRejected() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        // The baseline the interface holds no longer matches the device.
        var drifted = makeSector()
        drifted.bytes[0] = 4
        let outcome = try await applyDPI(service, 1600, 1600, baseline: drifted)
        #expect(outcome == .rejectedStale)
        #expect(device.writeCount == 0)
    }

    @Test("a verified write stores a backup and the device content matches")
    func verifiedWrite() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let outcome = try await applyDPI(service, 1600, 800)
        guard case .applied(let backup) = outcome else {
            Issue.record("expected an applied outcome, got \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(device.writeCount == 1)
        let written = ProfileSector(bytes: device.sector, sector: 1)
        #expect(written.dpiX == 1600)
        #expect(written.dpiY == 800)
        #expect(written.hasValidCRC)
        // Every byte outside the DPI words and the CRC stayed untouched.
        let original = makeSector()
        for index in 0..<253 where index != 9 && index != 10 && index != 11 && index != 12 {
            #expect(written.bytes[index] == original.bytes[index])
        }
    }

    @Test("a timeout while committing is never reported as verified")
    func commitTimeoutIsUncertain() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        device.behavior = .timeoutOnCommit
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let outcome = try await applyDPI(service, 1600, 1600)
        guard case .uncertainReason = outcome else {
            Issue.record("expected an uncertain outcome, got \(outcome)")
            return
        }
        #expect(!outcome.isApplied)
    }

    @Test("a read back that differs is reported as uncertain, not as a success")
    func mismatchedReadBack() async throws {
        let device = FakeSuperstrike(sector: makeSector().bytes)
        device.behavior = .corruptOnCommit
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _) = try makeService(device: device, store: store)
        let outcome = try await applyDPI(service, 1600, 1600)
        guard case .uncertainReason = outcome else {
            Issue.record("expected an uncertain outcome, got \(outcome)")
            return
        }
        #expect(!outcome.isApplied)
    }
}

/// Correlation and the framing rules that the apply path depends on.
@Suite("HID++ correlation")
struct HIDPPCorrelationTests {

    private func longReply(deviceIndex: UInt8, feature: UInt8, function: UInt8, software: UInt8, data: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11, deviceIndex, feature, (function << 4) | software]
        bytes.append(contentsOf: data)
        bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - data.count)))
        return bytes
    }

    @Test("an error reply fails the matching transaction")
    func errorReplyFailsTransaction() async throws {
        let transport = MockHIDPPTransport { request in
            // Answer with a HID++ 2.0 error: marker 0xFF, echoed feature and function.
            var bytes: [UInt8] = [0x11, request[1], 0xFF, request[2], request[3], 0x02]
            bytes.append(contentsOf: repeatElement(0, count: 14))
            return bytes
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(200))
        await #expect(throws: HIDPPError.deviceError(reason: 0x02)) {
            _ = try await client.request(featureIndex: 0x0C, function: 0x02)
        }
    }

    @Test("a notification with software ID 0 is ignored")
    func notificationIgnored() async throws {
        let transport = MockHIDPPTransport { _ in nil }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(150))
        transport.deliver(longReply(deviceIndex: 0xFF, feature: 0x0C, function: 0x02, software: 0x00, data: [0x01]))
        await #expect(throws: HIDPPError.self) {
            _ = try await client.request(featureIndex: 0x0C, function: 0x02)
        }
    }

    @Test("a reply for another feature does not answer the request")
    func unrelatedReplyIgnored() async throws {
        let transport = MockHIDPPTransport { request in
            // Answer with the same function but a different feature index.
            longReply(deviceIndex: request[1], feature: 0x0D, function: request[3] >> 4, software: request[3] & 0x0F, data: [0x01])
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(150))
        await #expect(throws: HIDPPError.self) {
            _ = try await client.request(featureIndex: 0x0C, function: 0x02)
        }
    }

    @Test("a silent device times out instead of hanging")
    func timeoutOnSilence() async throws {
        let transport = MockHIDPPTransport { _ in nil }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(120))
        await #expect(throws: HIDPPError.self) {
            _ = try await client.request(featureIndex: 0x0C, function: 0x02)
        }
    }

    @Test("rapid trigger switch is separate from its nonzero sensitivity")
    func rapidTriggerEncoding() async throws {
        let transport = MockHIDPPTransport { request in
            let feature = request[2]
            let function = request[3] >> 4
            let software = request[3] & 0x0F
            let payload = Array(request[4...])
            func frame(_ data: [UInt8]) -> [UInt8] {
                var bytes: [UInt8] = [0x11, request[1], feature, (function << 4) | software]
                bytes.append(contentsOf: data)
                bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - data.count)))
                return bytes
            }
            switch feature {
            case 0x00:
                // root getFeature: 0x1B0C lives at index 2
                if function == 0x00 { return frame([0x02, 0x00, 0x01]) }
                return frame([0x04, 0x02])
            case 0x02:
                if function == 0x00 { return frame([0x00, 0x03, 10 << 2, 5 << 2, 5 << 2]) }
                if function == 0x02 { return frame([payload[0], 2 << 2, (1 << 2) | 0x01, 3 << 2]) }
                return frame([])
            default:
                return nil
            }
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(200))
        let capabilities = try await client.readHitsCapabilities()
        #expect(capabilities.maxActuation == 10)
        #expect(capabilities.maxRapidTrigger == 5)
        #expect(capabilities.maxHaptics == 5)

        let config = try await client.readHitsButton(0)
        #expect(config.actuation == 2)
        #expect(config.rapidTrigger == 1)
        #expect(config.rapidTriggerFlag == 1)
        #expect(config.haptics == 3)

        // Disable only the enable bit; sensitivity remains valid.
        var off = config
        off.rapidTriggerEnabled = false
        try await client.setHitsButton(off, maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        let offFrame = transport.sentFrames.last!
        #expect(offFrame[4] == 0)
        #expect(offFrame[5] == 2 << 2)
        #expect(offFrame[6] == 1 << 2)
        #expect(offFrame[7] == 3 << 2)

        // Rapid trigger on: the firmware bit in bit 0 survives.
        var on = config
        on.rapidTrigger = 2
        try await client.setHitsButton(on, maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        let onFrame = transport.sentFrames.last!
        #expect(onFrame[6] == (2 << 2) | 0x01)
    }
}
