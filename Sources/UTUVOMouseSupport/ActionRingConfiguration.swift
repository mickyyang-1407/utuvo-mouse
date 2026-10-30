import Foundation

/// One action, never a macro or a sequence of arbitrary commands.
public enum RingAction: String, CaseIterable, Codable, Sendable {
    case none, copy, paste, cut, undo, redo, selectAll, finder, spotlight, screenshot, missionControl

    public var symbol: String {
        switch self {
        case .none: "minus"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .cut: "scissors"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .selectAll: "character.cursor.ibeam"
        case .finder: "folder"
        case .spotlight: "magnifyingglass"
        case .screenshot: "viewfinder"
        case .missionControl: "rectangle.3.group"
        }
    }
}

public struct ActionRingConfiguration: Equatable, Codable, Sendable {
    public var version = 1
    public var slots: [RingAction]

    public init(slots: [RingAction] = [.copy, .paste, .cut, .redo, .finder, .spotlight, .selectAll, .undo]) {
        self.slots = slots
    }

    public var isValid: Bool { version == 1 && slots.count == 8 }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.isValid else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
}

/// Eight clockwise directions, starting at the top; y increases downward.
/// The center and space beyond the menu cancel instead of choosing an action.
public enum ActionRingGeometry {
    public static func slot(x: Double, y: Double, deadZone: Double = 30, radius: Double = 190) -> Int? {
        guard x.isFinite, y.isFinite, deadZone >= 0, radius > deadZone else { return nil }
        let distance = hypot(x, y)
        guard distance >= deadZone, distance <= radius else { return nil }
        let turn = (atan2(y, x) + .pi / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return Int((turn / (.pi / 4)).rounded()) % 8
    }
}
