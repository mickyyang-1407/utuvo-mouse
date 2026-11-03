import Foundation
import Observation

/// An app-side profile for MX Master 4 M: the pointer and wheel values it sends.
///
/// The mouse has no onboard profiles, so a profile is only a saved set of
/// values. Unknown values are not saved and not sent.
public struct MXProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var dpi: Int?
    public var smartShiftMode: Int?
    public var smartShiftThreshold: Int?
    public var wheelInverted: Bool?
    public var wheelHighResolution: Bool?

    public init(id: UUID = UUID(), name: String, dpi: Int? = nil, smartShiftMode: Int? = nil,
                smartShiftThreshold: Int? = nil, wheelInverted: Bool? = nil, wheelHighResolution: Bool? = nil) {
        self.id = id
        self.name = name
        self.dpi = dpi
        self.smartShiftMode = smartShiftMode
        self.smartShiftThreshold = smartShiftThreshold
        self.wheelInverted = wheelInverted
        self.wheelHighResolution = wheelHighResolution
    }

    /// True when the profile holds at least one value to send.
    public var hasValues: Bool {
        dpi != nil || smartShiftMode != nil || smartShiftThreshold != nil || wheelInverted != nil || wheelHighResolution != nil
    }
}

/// The values a mouse reported, as the profile logic needs them.
public struct MXReadValues: Equatable, Sendable {
    public var dpi: Int?
    public var smartShiftMode: Int?
    public var smartShiftThreshold: Int?
    public var wheelInverted: Bool?
    public var wheelHighResolution: Bool?

    public init(dpi: Int? = nil, smartShiftMode: Int? = nil, smartShiftThreshold: Int? = nil,
                wheelInverted: Bool? = nil, wheelHighResolution: Bool? = nil) {
        self.dpi = dpi
        self.smartShiftMode = smartShiftMode
        self.smartShiftThreshold = smartShiftThreshold
        self.wheelInverted = wheelInverted
        self.wheelHighResolution = wheelHighResolution
    }
}

/// What applying a profile has to send. Nil means "leave as is".
public struct MXProfileWrite: Equatable, Sendable {
    public var dpi: Int?
    public var smartShiftMode: Int?
    public var smartShiftThreshold: Int?
    public var wheelInverted: Bool?
    public var wheelHighResolution: Bool?
    /// The profile's DPI is not one the mouse offers, so it was left out.
    public var skippedUnavailableDPI = false

    public var sendsSmartShift: Bool { smartShiftMode != nil || smartShiftThreshold != nil }
    public var sendsWheel: Bool { wheelInverted != nil || wheelHighResolution != nil }
    public var isEmpty: Bool { dpi == nil && !sendsSmartShift && !sendsWheel }
}

public enum MXProfileLogic {
    /// A profile made from the values the mouse reported. Unknown values stay out.
    public static func profile(named name: String, from values: MXReadValues) -> MXProfile {
        MXProfile(name: name, dpi: values.dpi, smartShiftMode: values.smartShiftMode,
                  smartShiftThreshold: values.smartShiftThreshold, wheelInverted: values.wheelInverted,
                  wheelHighResolution: values.wheelHighResolution)
    }

    /// Only the values that differ from what the mouse reported. A value the
    /// mouse did not report is sent, because its state is unknown.
    /// A DPI that the mouse does not list as available is never sent.
    public static func write(for profile: MXProfile, current: MXReadValues, availableDPI: [Int]) -> MXProfileWrite {
        func differs<T: Equatable>(_ wanted: T?, _ now: T?) -> T? {
            guard let wanted else { return nil }
            return wanted == now ? nil : wanted
        }
        var write = MXProfileWrite()
        if let dpi = differs(profile.dpi, current.dpi) {
            if availableDPI.contains(dpi) { write.dpi = dpi } else { write.skippedUnavailableDPI = true }
        }
        write.smartShiftMode = differs(profile.smartShiftMode, current.smartShiftMode)
        write.smartShiftThreshold = differs(profile.smartShiftThreshold, current.smartShiftThreshold)
        write.wheelInverted = differs(profile.wheelInverted, current.wheelInverted)
        write.wheelHighResolution = differs(profile.wheelHighResolution, current.wheelHighResolution)
        return write
    }

    /// The profile whose every saved value matches what the mouse reported.
    /// A profile with a value the mouse did not report never matches.
    public static func active(in profiles: [MXProfile], current: MXReadValues) -> MXProfile? {
        profiles.first { profile in
            guard profile.hasValues else { return false }
            func same<T: Equatable>(_ wanted: T?, _ now: T?) -> Bool { wanted == nil || (now != nil && wanted == now) }
            return same(profile.dpi, current.dpi)
                && same(profile.smartShiftMode, current.smartShiftMode)
                && same(profile.smartShiftThreshold, current.smartShiftThreshold)
                && same(profile.wheelInverted, current.wheelInverted)
                && same(profile.wheelHighResolution, current.wheelHighResolution)
        }
    }
}

/// The saved MX profiles. App-only data: nothing is written to the mouse here.
@MainActor
@Observable
public final class MXProfileStore {
    public static let defaultsKey = "mxProfiles.v1"
    public private(set) var profiles: [MXProfile] = []
    public private(set) var lastSaveFailed = false
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private let persists: Bool

    /// `persists: false` keeps profiles in memory only (demo): real saved profiles are never read or changed.
    public init(defaults: UserDefaults = .standard, persists: Bool = true) {
        self.defaults = defaults
        self.persists = persists
        if persists, let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([MXProfile].self, from: data) {
            profiles = decoded
        }
    }

    public func add(_ profile: MXProfile) {
        guard profile.hasValues else { return }
        profiles.append(profile)
        persist()
    }

    public func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        persist()
    }

    public func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    /// "Profile 1", "Profile 2"… the first number not in use.
    public func nextName(prefix: String) -> String {
        let used = Set(profiles.map(\.name))
        var number = profiles.count + 1
        while used.contains("\(prefix) \(number)") { number += 1 }
        return "\(prefix) \(number)"
    }

    private func persist() {
        guard persists else { return }
        do {
            defaults.set(try JSONEncoder().encode(profiles), forKey: Self.defaultsKey)
            lastSaveFailed = false
        } catch {
            lastSaveFailed = true
        }
    }
}
