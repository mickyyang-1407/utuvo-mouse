import SwiftUI
import UTUVOMouseCore
import UTUVOMouseSupport

/// Body colors: what each line usually ships in.
enum MouseFinish {
    case graphite, paleGray, black, white, rose

    static func finish(model: MouseModel, family: MouseShapeFamily) -> MouseFinish {
        switch family {
        case .esportsSymmetric, .esportsErgo, .angular, .sideGrid, .receiver: return .black
        case .flatPebble: return .rose
        default: return model == .mxMaster4 ? .graphite : .graphite
        }
    }

    var top: Color {
        switch self {
        case .graphite: return Color(red: 0.36, green: 0.37, blue: 0.40)
        case .paleGray: return Color(red: 0.86, green: 0.86, blue: 0.84)
        case .black: return Color(red: 0.20, green: 0.20, blue: 0.22)
        case .white: return Color(white: 0.96)
        case .rose: return Color(red: 0.93, green: 0.80, blue: 0.78)
        }
    }
    var bottom: Color {
        switch self {
        case .graphite: return Color(red: 0.20, green: 0.21, blue: 0.23)
        case .paleGray: return Color(red: 0.70, green: 0.70, blue: 0.68)
        case .black: return Color(red: 0.08, green: 0.08, blue: 0.09)
        case .white: return Color(white: 0.80)
        case .rose: return Color(red: 0.80, green: 0.62, blue: 0.60)
        }
    }
    var isLight: Bool { self == .paleGray || self == .white || self == .rose }
}

/// A drawn mouse, top view, in a 100 × 140 design space.
struct MouseArt: View {
    let family: MouseShapeFamily
    var finish: MouseFinish = .graphite
    var accent: Color = MouseTheme.accent

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 100, size.height / 140)
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 140 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            draw(&context)
        }
        .aspectRatio(100 / 140, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var line: Color { finish.isLight ? .black.opacity(0.22) : .white.opacity(0.16) }
    private var detail: Color { finish.isLight ? .black.opacity(0.55) : Color(white: 0.06) }
    private var gradient: GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [finish.top, finish.bottom]), startPoint: CGPoint(x: 20, y: 0), endPoint: CGPoint(x: 80, y: 140))
    }

    private func draw(_ context: inout GraphicsContext) {
        if family == .receiver { drawReceiver(&context); return }
        let body = bodyPath
        // Soft contact shadow.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.fill(Path(ellipseIn: CGRect(x: 18, y: 120, width: 64, height: 14)), with: .color(.black.opacity(0.22)))
        }
        context.fill(body, with: gradient)
        context.stroke(body, with: .color(line), lineWidth: 1)
        // Highlight along the top.
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(ellipseIn: CGRect(x: 18, y: -10, width: 60, height: 50)), with: .color(.white.opacity(finish.isLight ? 0.35 : 0.10)))
        }
        drawButtons(&context)
        drawFeatures(&context)
    }

    // MARK: Bodies

    private var bodyPath: Path {
        var p = Path()
        switch family {
        case .ergoThumbRest:
            p.move(to: CGPoint(x: 52, y: 6))
            p.addCurve(to: CGPoint(x: 86, y: 52), control1: CGPoint(x: 74, y: 6), control2: CGPoint(x: 88, y: 26))
            p.addCurve(to: CGPoint(x: 72, y: 132), control1: CGPoint(x: 84, y: 86), control2: CGPoint(x: 84, y: 122))
            p.addCurve(to: CGPoint(x: 22, y: 128), control1: CGPoint(x: 58, y: 140), control2: CGPoint(x: 34, y: 138))
            p.addCurve(to: CGPoint(x: 6, y: 92), control1: CGPoint(x: 10, y: 120), control2: CGPoint(x: 2, y: 104))
            p.addCurve(to: CGPoint(x: 20, y: 70), control1: CGPoint(x: 8, y: 82), control2: CGPoint(x: 18, y: 80))
            p.addCurve(to: CGPoint(x: 52, y: 6), control1: CGPoint(x: 18, y: 36), control2: CGPoint(x: 30, y: 6))
        case .compact:
            p.addRoundedRect(in: CGRect(x: 24, y: 14, width: 52, height: 112), cornerSize: CGSize(width: 26, height: 30))
        case .flatPebble:
            p.addRoundedRect(in: CGRect(x: 16, y: 18, width: 68, height: 104), cornerSize: CGSize(width: 34, height: 40))
        case .vertical:
            p.move(to: CGPoint(x: 46, y: 10))
            p.addCurve(to: CGPoint(x: 82, y: 70), control1: CGPoint(x: 72, y: 12), control2: CGPoint(x: 84, y: 40))
            p.addCurve(to: CGPoint(x: 58, y: 130), control1: CGPoint(x: 82, y: 104), control2: CGPoint(x: 74, y: 128))
            p.addCurve(to: CGPoint(x: 18, y: 108), control1: CGPoint(x: 38, y: 132), control2: CGPoint(x: 18, y: 124))
            p.addCurve(to: CGPoint(x: 46, y: 10), control1: CGPoint(x: 16, y: 70), control2: CGPoint(x: 24, y: 12))
        case .thumbTrackball:
            p.move(to: CGPoint(x: 54, y: 8))
            p.addCurve(to: CGPoint(x: 88, y: 64), control1: CGPoint(x: 78, y: 8), control2: CGPoint(x: 90, y: 34))
            p.addCurve(to: CGPoint(x: 64, y: 132), control1: CGPoint(x: 88, y: 102), control2: CGPoint(x: 80, y: 128))
            p.addCurve(to: CGPoint(x: 12, y: 112), control1: CGPoint(x: 40, y: 138), control2: CGPoint(x: 14, y: 130))
            p.addCurve(to: CGPoint(x: 54, y: 8), control1: CGPoint(x: 8, y: 66), control2: CGPoint(x: 28, y: 8))
        case .esportsSymmetric:
            p.move(to: CGPoint(x: 50, y: 6))
            p.addCurve(to: CGPoint(x: 78, y: 46), control1: CGPoint(x: 68, y: 6), control2: CGPoint(x: 78, y: 24))
            p.addCurve(to: CGPoint(x: 80, y: 104), control1: CGPoint(x: 78, y: 66), control2: CGPoint(x: 84, y: 84))
            p.addCurve(to: CGPoint(x: 20, y: 104), control1: CGPoint(x: 76, y: 142), control2: CGPoint(x: 24, y: 142))
            p.addCurve(to: CGPoint(x: 22, y: 46), control1: CGPoint(x: 16, y: 84), control2: CGPoint(x: 22, y: 66))
            p.addCurve(to: CGPoint(x: 50, y: 6), control1: CGPoint(x: 22, y: 24), control2: CGPoint(x: 32, y: 6))
        case .esportsErgo:
            p.move(to: CGPoint(x: 48, y: 6))
            p.addCurve(to: CGPoint(x: 82, y: 54), control1: CGPoint(x: 70, y: 6), control2: CGPoint(x: 84, y: 28))
            p.addCurve(to: CGPoint(x: 72, y: 128), control1: CGPoint(x: 82, y: 90), control2: CGPoint(x: 82, y: 118))
            p.addCurve(to: CGPoint(x: 22, y: 122), control1: CGPoint(x: 56, y: 140), control2: CGPoint(x: 30, y: 138))
            p.addCurve(to: CGPoint(x: 20, y: 44), control1: CGPoint(x: 14, y: 100), control2: CGPoint(x: 20, y: 66))
            p.addCurve(to: CGPoint(x: 48, y: 6), control1: CGPoint(x: 20, y: 22), control2: CGPoint(x: 30, y: 6))
        case .angular:
            p.move(to: CGPoint(x: 36, y: 6))
            p.addLine(to: CGPoint(x: 66, y: 6))
            p.addLine(to: CGPoint(x: 84, y: 30))
            p.addLine(to: CGPoint(x: 80, y: 80))
            p.addLine(to: CGPoint(x: 86, y: 108))
            p.addQuadCurve(to: CGPoint(x: 40, y: 134), control: CGPoint(x: 76, y: 140))
            p.addLine(to: CGPoint(x: 8, y: 104))
            p.addLine(to: CGPoint(x: 16, y: 78))
            p.addLine(to: CGPoint(x: 18, y: 30))
            p.closeSubpath()
        case .sideGrid:
            p.move(to: CGPoint(x: 50, y: 6))
            p.addCurve(to: CGPoint(x: 84, y: 56), control1: CGPoint(x: 72, y: 6), control2: CGPoint(x: 86, y: 28))
            p.addCurve(to: CGPoint(x: 70, y: 132), control1: CGPoint(x: 82, y: 94), control2: CGPoint(x: 82, y: 122))
            p.addCurve(to: CGPoint(x: 14, y: 116), control1: CGPoint(x: 52, y: 140), control2: CGPoint(x: 18, y: 136))
            p.addCurve(to: CGPoint(x: 50, y: 6), control1: CGPoint(x: 8, y: 70), control2: CGPoint(x: 26, y: 6))
        case .standardOval, .receiver:
            p.addEllipse(in: CGRect(x: 20, y: 10, width: 60, height: 120))
        }
        return p
    }

    // MARK: Buttons, wheel and family details

    private var splitBottom: CGFloat {
        switch family {
        case .flatPebble: return 46
        case .angular: return 62
        default: return 54
        }
    }

    private var wheelCenter: CGPoint {
        switch family {
        case .ergoThumbRest: return CGPoint(x: 54, y: 30)
        case .vertical: return CGPoint(x: 50, y: 34)
        case .thumbTrackball: return CGPoint(x: 60, y: 30)
        default: return CGPoint(x: 50, y: 30)
        }
    }

    private func drawButtons(_ context: inout GraphicsContext) {
        let wheel = wheelCenter
        var split = Path()
        let splitTop: CGFloat = switch family {
        case .flatPebble: 20
        case .compact: 16
        case .standardOval: 12
        case .vertical: 12
        default: 8
        }
        split.move(to: CGPoint(x: wheel.x, y: splitTop))
        split.addLine(to: CGPoint(x: wheel.x, y: splitBottom))
        if family != .flatPebble && family != .vertical {
            var seam = Path()
            seam.move(to: CGPoint(x: 24, y: splitBottom + 6))
            seam.addQuadCurve(to: CGPoint(x: 78, y: splitBottom + 6), control: CGPoint(x: 51, y: splitBottom + 16))
            context.stroke(seam, with: .color(line), lineWidth: 0.9)
        }
        context.stroke(split, with: .color(line), lineWidth: 1)
        // Wheel well and wheel.
        let wheelRect = CGRect(x: wheel.x - 4.5, y: wheel.y - 10, width: 9, height: 20)
        context.fill(Path(roundedRect: wheelRect.insetBy(dx: -2, dy: -2), cornerRadius: 6), with: .color(detail.opacity(0.65)))
        context.fill(Path(roundedRect: wheelRect, cornerRadius: 4.5), with: .color(Color(white: 0.42)))
        for i in 0..<6 {
            let y = wheelRect.minY + 3 + CGFloat(i) * 2.8
            context.fill(Path(CGRect(x: wheelRect.minX + 1.6, y: y, width: wheelRect.width - 3.2, height: 0.9)), with: .color(.white.opacity(0.28)))
        }
    }

    private func drawFeatures(_ context: inout GraphicsContext) {
        switch family {
        case .ergoThumbRest:
            // Side buttons, thumb wheel and the gesture pad on the thumb shelf.
            sideButton(&context, CGRect(x: 15, y: 56, width: 8, height: 9))
            sideButton(&context, CGRect(x: 15, y: 67, width: 8, height: 9))
            context.fill(Path(roundedRect: CGRect(x: 10, y: 80, width: 14, height: 5), cornerRadius: 2.5), with: .color(Color(white: 0.45)))
            context.fill(Path(ellipseIn: CGRect(x: 10, y: 96, width: 8, height: 8)), with: .color(accent.opacity(0.85)))
            dot(&context, CGPoint(x: 54, y: 48))
        case .compact:
            sideButton(&context, CGRect(x: 21, y: 58, width: 5, height: 9))
            sideButton(&context, CGRect(x: 21, y: 69, width: 5, height: 9))
            dot(&context, CGPoint(x: 50, y: 48))
        case .flatPebble:
            break
        case .vertical:
            // The thumb side of a vertical mouse, seen from above.
            var fin = Path()
            fin.move(to: CGPoint(x: 30, y: 36)); fin.addCurve(to: CGPoint(x: 28, y: 110), control1: CGPoint(x: 22, y: 60), control2: CGPoint(x: 22, y: 92))
            context.stroke(fin, with: .color(line), lineWidth: 1.2)
            sideButton(&context, CGRect(x: 22, y: 60, width: 6, height: 9))
            sideButton(&context, CGRect(x: 22, y: 71, width: 6, height: 9))
        case .thumbTrackball:
            let ball = CGRect(x: 14, y: 70, width: 30, height: 30)
            context.fill(Path(ellipseIn: ball.insetBy(dx: -3, dy: -3)), with: .color(detail.opacity(0.8)))
            context.fill(Path(ellipseIn: ball), with: .linearGradient(Gradient(colors: [accent.opacity(0.95), accent.opacity(0.55)]),
                                                                    startPoint: CGPoint(x: ball.minX, y: ball.minY), endPoint: CGPoint(x: ball.maxX, y: ball.maxY)))
            context.fill(Path(ellipseIn: CGRect(x: ball.minX + 6, y: ball.minY + 5, width: 8, height: 6)), with: .color(.white.opacity(0.45)))
        case .esportsSymmetric:
            sideButton(&context, CGRect(x: 19, y: 56, width: 4, height: 11))
            sideButton(&context, CGRect(x: 19, y: 69, width: 4, height: 11))
        case .esportsErgo:
            sideButton(&context, CGRect(x: 18, y: 54, width: 5, height: 11))
            sideButton(&context, CGRect(x: 18, y: 67, width: 5, height: 11))
            context.fill(Path(roundedRect: CGRect(x: 44, y: 116, width: 12, height: 6), cornerRadius: 3), with: .color(accent.opacity(0.8)))
        case .angular:
            // G-shift style extra buttons and the RGB strip.
            sideButton(&context, CGRect(x: 26, y: 12, width: 8, height: 12))
            sideButton(&context, CGRect(x: 26, y: 26, width: 8, height: 10))
            sideButton(&context, CGRect(x: 14, y: 70, width: 6, height: 10))
            sideButton(&context, CGRect(x: 14, y: 82, width: 6, height: 10))
            var strip = Path()
            strip.move(to: CGPoint(x: 62, y: 96)); strip.addLine(to: CGPoint(x: 76, y: 112))
            context.stroke(strip, with: .color(accent), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        case .sideGrid:
            for row in 0..<4 { for col in 0..<3 {
                context.fill(Path(roundedRect: CGRect(x: 12 + CGFloat(col) * 6, y: 62 + CGFloat(row) * 8, width: 4.5, height: 6), cornerRadius: 1.2),
                             with: .color(accent.opacity(0.75)))
            } }
        case .standardOval, .receiver:
            break
        }
    }

    private func sideButton(_ context: inout GraphicsContext, _ rect: CGRect) {
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(detail.opacity(0.75)))
    }

    private func dot(_ context: inout GraphicsContext, _ point: CGPoint) {
        context.fill(Path(roundedRect: CGRect(x: point.x - 3, y: point.y - 1.5, width: 6, height: 3), cornerRadius: 1.5), with: .color(detail.opacity(0.6)))
    }

    private func drawReceiver(_ context: inout GraphicsContext) {
        let body = Path(roundedRect: CGRect(x: 32, y: 40, width: 36, height: 54), cornerRadius: 8)
        context.fill(body, with: gradient)
        context.stroke(body, with: .color(line), lineWidth: 1)
        let plug = Path(roundedRect: CGRect(x: 38, y: 94, width: 24, height: 22), cornerRadius: 2)
        context.fill(plug, with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.62)]), startPoint: CGPoint(x: 38, y: 94), endPoint: CGPoint(x: 62, y: 116)))
        context.fill(Path(ellipseIn: CGRect(x: 45, y: 58, width: 10, height: 10)), with: .color(accent.opacity(0.85)))
    }
}

extension DeviceSnapshot {
    var shapeFamily: MouseShapeFamily {
        MouseShapeFamily.family(model: identity.model, productName: identity.productName, productID: identity.productID)
    }
}
