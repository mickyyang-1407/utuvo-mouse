import Foundation
import Testing
import UTUVOMouseSupport

@Suite("MX app-side profiles")
@MainActor
struct MXProfileTests {
    private let reported = MXReadValues(dpi: 1600, smartShiftMode: 2, smartShiftThreshold: 10,
                                        wheelInverted: false, wheelHighResolution: true)

    @Test("saving keeps only the values the mouse reported")
    func saveSkipsUnknown() {
        let profile = MXProfileLogic.profile(named: "Work", from: MXReadValues(dpi: 800))
        #expect(profile.dpi == 800)
        #expect(profile.smartShiftMode == nil && profile.wheelInverted == nil)
        #expect(profile.hasValues)
        #expect(!MXProfileLogic.profile(named: "Empty", from: MXReadValues()).hasValues)
    }

    @Test("applying sends only what differs")
    func writeOnlyDifferences() {
        let profile = MXProfile(name: "Edit", dpi: 3200, smartShiftMode: 2, smartShiftThreshold: 10,
                                wheelInverted: true, wheelHighResolution: true)
        let write = MXProfileLogic.write(for: profile, current: reported, availableDPI: [800, 1600, 3200])
        #expect(write.dpi == 3200)
        #expect(!write.sendsSmartShift)
        #expect(write.wheelInverted == true && write.wheelHighResolution == nil)
    }

    @Test("a value the mouse did not report is sent, never assumed")
    func unknownIsSent() {
        let profile = MXProfile(name: "P", smartShiftMode: 1)
        let write = MXProfileLogic.write(for: profile, current: MXReadValues(dpi: 1600), availableDPI: [])
        #expect(write.smartShiftMode == 1)
    }

    @Test("a DPI the mouse does not list is never sent")
    func unavailableDPIRefused() {
        let profile = MXProfile(name: "P", dpi: 12345)
        let write = MXProfileLogic.write(for: profile, current: reported, availableDPI: [800, 1600])
        #expect(write.isEmpty)
        #expect(write.skippedUnavailableDPI)
        // Nothing to send here is not a match: the profile is not active.
        #expect(MXProfileLogic.active(in: [profile], current: reported) == nil)
    }

    @Test("an in-memory store never reads or writes saved profiles")
    func ephemeralStore() throws {
        let suite = "com.utuvo.mouse.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        MXProfileStore(defaults: defaults).add(MXProfile(name: "Real", dpi: 800))

        let demo = MXProfileStore(defaults: defaults, persists: false)
        #expect(demo.profiles.isEmpty)
        demo.add(MXProfile(name: "Demo", dpi: 1600))
        #expect(MXProfileStore(defaults: defaults).profiles.map(\.name) == ["Real"])
    }

    @Test("an identical profile sends nothing")
    func identicalIsEmpty() {
        let profile = MXProfileLogic.profile(named: "Same", from: reported)
        #expect(MXProfileLogic.write(for: profile, current: reported, availableDPI: [1600]).isEmpty)
    }

    @Test("active only when every saved value is reported and equal")
    func activeMatching() {
        let match = MXProfile(name: "A", dpi: 1600, smartShiftMode: 2)
        let other = MXProfile(name: "B", dpi: 3200)
        #expect(MXProfileLogic.active(in: [other, match], current: reported)?.name == "A")
        // The mouse did not report SmartShift: the profile cannot be claimed active.
        #expect(MXProfileLogic.active(in: [match], current: MXReadValues(dpi: 1600)) == nil)
        #expect(MXProfileLogic.active(in: [MXProfile(name: "Empty")], current: reported) == nil)
    }

    @Test("store round-trips, renames, removes and numbers new names")
    func storeRoundTrip() throws {
        let suite = "com.utuvo.mouse.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MXProfileStore(defaults: defaults)
        #expect(store.nextName(prefix: "Profile") == "Profile 1")
        store.add(MXProfile(name: "Profile 1", dpi: 800))
        store.add(MXProfile(name: "Ignored"))
        #expect(store.profiles.count == 1)
        #expect(store.nextName(prefix: "Profile") == "Profile 2")

        let id = store.profiles[0].id
        store.rename(id, to: "  Gaming  ")
        store.rename(id, to: "   ")
        #expect(MXProfileStore(defaults: defaults).profiles.map(\.name) == ["Gaming"])

        store.remove(id)
        #expect(MXProfileStore(defaults: defaults).profiles.isEmpty)
    }
}
