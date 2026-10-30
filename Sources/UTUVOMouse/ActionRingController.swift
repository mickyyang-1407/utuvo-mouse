import AppKit
import SwiftUI
import Carbon.HIToolbox
import UTUVOMouseSupport
import UTUVOMouseIO

/// A nonactivating HUD keeps keyboard shortcuts directed at the original app.
@Observable
final class ActionRingController {
    var configuration: ActionRingConfiguration
    var highlighted: Int?
    var isPreview = false
    private(set) var storageError: String?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var presentationID = UUID()
    @ObservationIgnored private let pointerLocation: () -> NSPoint
    @ObservationIgnored private var localKeys: Any?
    @ObservationIgnored private var globalKeys: Any?
    @ObservationIgnored private var origin = NSPoint.zero
    @ObservationIgnored private var initialPointer = NSPoint.zero
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var targetPID: pid_t?
    private static let preferenceKey = "actionRing.configuration.v1"

    init(isDemo: Bool, pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
        defaults = isDemo ? nil : .standard
        if let data = defaults?.data(forKey: Self.preferenceKey) {
            do { configuration = try ActionRingConfiguration.decode(data) }
            catch {
                configuration = ActionRingConfiguration()
                storageError = AppLocalization.text("ring.storageError")
            }
        } else { configuration = ActionRingConfiguration() }
    }

    func setAction(_ action: RingAction, at slot: Int) {
        guard configuration.slots.indices.contains(slot) else { return }
        configuration.slots[slot] = action
        if let data = try? JSONEncoder().encode(configuration) {
            defaults?.set(data, forKey: Self.preferenceKey)
            storageError = nil
        }
    }

    func input(_ down: Bool?) {
        if down == true { if !suspended { present(preview: false) } }
        else if down == false { finish(); suspended = false }
        else { cancel(); suspended = false }
    }

    func present(preview: Bool) {
        cancel()
        isPreview = preview
        highlighted = nil
        initialPointer = pointerLocation()
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let screen = NSScreen.screens.first { $0.frame.contains(initialPointer) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let half: CGFloat = 218
        origin = NSPoint(x: min(max(initialPointer.x, frame.minX + half), frame.maxX - half),
                         y: min(max(initialPointer.y, frame.minY + half), frame.maxY - half))
        let window = NSPanel(contentRect: NSRect(x: origin.x-half, y: origin.y-half, width: half*2, height: half*2),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        let content = RingTrackingView(rootView: RingHUD(controller: self))
        content.pointerMoved = { [weak self] point in self?.trackPointer(at: point) }
        content.pointerExited = { [weak self] in self?.highlighted = nil }
        window.contentView = content
        panel = window
        window.orderFrontRegardless()
        let currentPresentation = presentationID
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.presentationID == currentPresentation else { return }
            self.escape()
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelIfTargetChanged() }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.escape(); return nil }
            return event
        }
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.escape() } }
        }
    }

    private func trackPointer(at location: NSPoint? = nil) {
        guard panel != nil else { return }
        let point = location ?? pointerLocation()
        guard hypot(point.x-initialPointer.x, point.y-initialPointer.y) >= 8 else { highlighted = nil; return }
        let selection = ActionRingGeometry.slot(x: point.x-origin.x, y: origin.y-point.y)
        if highlighted != selection { highlighted = selection }
    }

    private func cancelIfTargetChanged() {
        guard panel != nil, !isPreview else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID { escape() }
    }

    private func finish() {
        guard panel != nil else { return }
        if !isPreview, NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID { escape(); return }
        trackPointer()
        guard panel != nil else { return }
        let action = highlighted.map { configuration.slots[$0] }
        let preview = isPreview
        cancel()
        if !preview, let action { perform(action) }
    }

    func choose(_ slot: Int) {
        guard configuration.slots.indices.contains(slot) else { return }
        if !isPreview, NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID { escape(); return }
        let action = configuration.slots[slot]
        let preview = isPreview
        cancel()
        suspended = !preview // Ignore the later physical release after a click.
        if !preview { perform(action) }
    }

    func escape() { let physical = !isPreview; cancel(); suspended = physical }

    func cancel() {
        presentationID = UUID()
        timeoutTask?.cancel(); timeoutTask = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if let localKeys { NSEvent.removeMonitor(localKeys) }; localKeys = nil
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }; globalKeys = nil
        panel?.orderOut(nil); panel = nil
        highlighted = nil
    }

    private func perform(_ action: RingAction) {
        guard MXButtonRemapper.hasAccessibilityPermission else { return }
        let command: (CGKeyCode, CGEventFlags)?
        switch action {
        case .none: return
        case .finder:
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)); return
        case .copy: command = (CGKeyCode(kVK_ANSI_C), .maskCommand)
        case .paste: command = (CGKeyCode(kVK_ANSI_V), .maskCommand)
        case .cut: command = (CGKeyCode(kVK_ANSI_X), .maskCommand)
        case .undo: command = (CGKeyCode(kVK_ANSI_Z), .maskCommand)
        case .redo: command = (CGKeyCode(kVK_ANSI_Z), [.maskCommand, .maskShift])
        case .selectAll: command = (CGKeyCode(kVK_ANSI_A), .maskCommand)
        case .spotlight: command = (CGKeyCode(kVK_Space), .maskCommand)
        case .screenshot: command = (CGKeyCode(kVK_ANSI_4), [.maskCommand, .maskShift])
        case .missionControl: command = (CGKeyCode(kVK_UpArrow), .maskControl)
        }
        guard let (key, flags) = command,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { return }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
}

/// AppKit supplies movement only while the HUD is being used. No idle polling.
final class RingTrackingView: NSHostingView<RingHUD> {
    var pointerMoved: ((NSPoint) -> Void)?
    var pointerExited: (() -> Void)?
    private var pointerArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        if let window { pointerMoved?(window.convertPoint(toScreen: event.locationInWindow)) }
        super.mouseMoved(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let window { pointerMoved?(window.convertPoint(toScreen: event.locationInWindow)) }
        super.mouseDragged(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerExited?()
        super.mouseExited(with: event)
    }
}

struct RingHUD: View {
    @Bindable var controller: ActionRingController

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial).frame(width: 354, height: 354)
                .overlay(Circle().stroke(.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            ForEach(0..<8, id: \.self) { slot in
                let angle = Double(slot) * .pi / 4 - .pi / 2
                let action = controller.configuration.slots[slot]
                Button { controller.choose(slot) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: action.symbol).font(.system(size: 23, weight: .medium))
                        Text(AppLocalization.text("ring.action." + action.rawValue)).font(.system(size: 11, weight: .medium)).lineLimit(2)
                    }
                    .frame(width: 82, height: 70)
                    .background(controller.highlighted == slot ? MouseTheme.accent.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(controller.highlighted == slot ? MouseTheme.accent : .primary)
                }
                .buttonStyle(.plain)
                .offset(x: cos(angle)*128, y: sin(angle)*128)
            }
            VStack(spacing: 5) {
                Image(systemName: "cursorarrow.rays").font(.title3)
                Text(AppLocalization.text(controller.isPreview ? "ring.preview" : "ring.release"))
                    .font(.system(size: 11, weight: .medium)).multilineTextAlignment(.center)
                Button("Esc") { controller.escape() }.font(.system(size: 10, design: .monospaced)).buttonStyle(.plain).foregroundStyle(.secondary)
            }.frame(width: 90)
        }
        .frame(width: 436, height: 436)
        .tint(MouseTheme.accent)
    }
}
