import SwiftUI
import AppKit
import UTUVOMouseCore

enum MouseTheme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.48, green: 0.78, blue: 0.69, alpha: 1)
            : NSColor(red: 0.13, green: 0.43, blue: 0.36, alpha: 1)
    })
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.105, alpha: 1) : NSColor(red: 0.967, green: 0.968, blue: 0.960, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.145, alpha: 1) : .white
    })
}

struct MouseGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            configuration.content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MouseTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.065), lineWidth: 1))
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
                    Text(model == .mxMaster4 ? "mx" : "G").font(.system(size: 17, weight: .semibold))
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
            VStack(spacing: 11) {
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : .secondary)
                Capsule().fill(selected ? MouseTheme.accent : .clear).frame(height: 3)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
