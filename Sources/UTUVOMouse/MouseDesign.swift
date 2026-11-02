import SwiftUI
import AppKit
import UTUVOMouseCore

enum MouseTheme {
    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    /// Actions: the one blue that means "do this".
    static let accent = dynamic(dark: NSColor(red: 0.30, green: 0.56, blue: 1.00, alpha: 1),
                                light: NSColor(red: 0.04, green: 0.42, blue: 0.93, alpha: 1))
    /// State colors only. Never decoration.
    static let ok = dynamic(dark: NSColor(red: 0.33, green: 0.80, blue: 0.48, alpha: 1),
                            light: NSColor(red: 0.12, green: 0.56, blue: 0.29, alpha: 1))
    static let attention = dynamic(dark: NSColor(red: 0.98, green: 0.62, blue: 0.26, alpha: 1),
                                   light: NSColor(red: 0.85, green: 0.45, blue: 0.05, alpha: 1))
    static let canvas = dynamic(dark: NSColor(red: 0.110, green: 0.118, blue: 0.140, alpha: 1),
                                light: NSColor(red: 0.965, green: 0.966, blue: 0.972, alpha: 1))
    static let surface = dynamic(dark: NSColor(red: 0.150, green: 0.160, blue: 0.188, alpha: 1), light: .white)
    static let hairline = dynamic(dark: NSColor(white: 1, alpha: 0.07), light: NSColor(white: 0, alpha: 0.07))
}

struct MouseGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MouseTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MouseTheme.hairline, lineWidth: 1))
    }
}

extension MouseModel {
    var tileColor: Color {
        switch self {
        case .mxMaster4: return Color(red: 0.36, green: 0.42, blue: 0.95)
        case .superstrike: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .receiver: return Color(red: 0.25, green: 0.66, blue: 0.70)
        case .unknown: return Color(white: 0.52)
        }
    }
}

/// Rounded-square icon tile, as in a macOS sidebar.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.92), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// Small colored capsule beside a title: state only.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// Diagonal hatching for the part of a bar that is not "solid".
struct HatchFill: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1.2)
        }
        .background(color.opacity(0.10))
    }
}

/// Battery bar: solid is charge left, hatched is used. Unknown is all hatched, never guessed.
struct ChargeBar: View {
    let percentage: Int?

    var body: some View {
        let fraction = CGFloat(min(max(percentage ?? 0, 0), 100)) / 100
        let tint = (percentage ?? 100) <= 20 ? MouseTheme.attention : MouseTheme.ok
        GeometryReader { proxy in
            let inner = proxy.size.width - 12
            HStack(spacing: 4) {
                if percentage != nil, fraction > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint)
                        .frame(width: max(inner * fraction - (fraction < 1 ? 2 : 0), 6))
                }
                if fraction < 1 {
                    HatchFill(color: percentage == nil ? .secondary : tint)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(6)
        }
        .frame(height: 40)
        .background(MouseTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(MouseTheme.hairline, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(percentage.map { "\($0)%" } ?? AppLocalization.text("app.unknownBattery"))
    }
}

/// The one blue action, as a capsule. Fixed color: never depends on window focus.
struct PrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(MouseTheme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// Conclusion card: one sentence of state, one optional action.
struct NoticeCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    var actionTitle: String?
    var actionDisabled = false
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.regular).disabled(actionDisabled)
            }
        }
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

/// Original vector illustration. No third-party product images or assets.
struct MouseIllustration: View {
    let model: MouseModel
    var compact = false

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 150, proxy.size.height / 180)
            ZStack {
                Ellipse().fill(.black.opacity(0.10)).frame(width: 84, height: 14).blur(radius: 8).offset(y: 72)
                if model == .mxMaster4 {
                    RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.22))
                        .frame(width: 64, height: 92).rotationEffect(.degrees(24)).offset(x: -30, y: 30)
                }
                RoundedRectangle(cornerRadius: 43)
                    .fill(LinearGradient(colors: model == .mxMaster4 ? [Color(white: 0.36), Color(white: 0.16)] : [Color(white: 0.99), Color(white: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 95, height: 154)
                    .overlay(RoundedRectangle(cornerRadius: 43).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.14), radius: 5, x: 2, y: 5)
                Path { path in
                    path.move(to: CGPoint(x: 75, y: 15)); path.addLine(to: CGPoint(x: 75, y: 73))
                    path.move(to: CGPoint(x: 31, y: 72)); path.addQuadCurve(to: CGPoint(x: 119, y: 72), control: CGPoint(x: 75, y: 83))
                }.stroke(.black.opacity(0.2), lineWidth: 0.8).frame(width: 150, height: 180)
                RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.12)).frame(width: 15, height: 37).offset(y: -48)
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { _ in Rectangle().fill(.white.opacity(0.26)).frame(width: 9, height: 1) }
                }.offset(y: -48)
                if !compact {
                    Circle().fill(MouseTheme.accent).frame(width: 4, height: 4).offset(y: -13)
                    Text(model == .mxMaster4 ? "mx" : model == .superstrike ? "G" : "").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model == .mxMaster4 ? Color.white.opacity(0.65) : Color.black.opacity(0.55)).offset(y: 40)
                }
            }
            .frame(width: 150, height: 180)
            .scaleEffect(scale)
            .position(x: proxy.size.width/2, y: proxy.size.height/2)
        }
        .accessibilityHidden(true)
    }
}

struct DetailTabButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(selected ? MouseTheme.surface : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? MouseTheme.hairline : .clear, lineWidth: 1))
                .fixedSize()
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
