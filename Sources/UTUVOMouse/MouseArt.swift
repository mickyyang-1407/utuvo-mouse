import SwiftUI
import UTUVOMouseCore
import UTUVOMouseSupport

/// Body colors. macOS cannot report a mouse's color, so the person picks one.
enum MouseFinish: String, CaseIterable, Sendable {
    case graphite, black, paleGray, white, rose, lilac

    /// The colors a family is sold in, most common first.
    static func options(model: MouseModel, family: MouseShapeFamily) -> [MouseFinish] {
        switch family {
        case .ergoThumbRest: return [.graphite, .paleGray, .black]
        case .compact: return [.graphite, .paleGray, .rose, .black]
        case .flatPebble: return [.graphite, .white, .rose, .lilac]
        case .vertical: return [.graphite, .white, .rose]
        case .thumbTrackball: return [.graphite, .black, .white]
        case .esportsSymmetric: return model == .superstrike ? [.white, .black] : [.black, .white, .lilac]
        case .esportsErgo, .angular, .sideGrid: return [.black, .white]
        case .standardOval: return [.graphite, .black, .paleGray, .lilac]
        case .receiver: return [.black]
        }
    }

    static func finish(model: MouseModel, family: MouseShapeFamily) -> MouseFinish {
        options(model: model, family: family)[0]
    }

    var top: Color {
        switch self {
        case .graphite: return Color(red: 0.33, green: 0.335, blue: 0.35)
        case .paleGray: return Color(red: 0.88, green: 0.88, blue: 0.86)
        case .black: return Color(red: 0.19, green: 0.19, blue: 0.20)
        case .white: return Color(white: 0.98)
        case .rose: return Color(red: 0.95, green: 0.84, blue: 0.82)
        case .lilac: return Color(red: 0.84, green: 0.80, blue: 0.93)
        }
    }
    var bottom: Color {
        switch self {
        case .graphite: return Color(red: 0.16, green: 0.165, blue: 0.175)
        case .paleGray: return Color(red: 0.72, green: 0.72, blue: 0.70)
        case .black: return Color(red: 0.06, green: 0.06, blue: 0.07)
        case .white: return Color(white: 0.82)
        case .rose: return Color(red: 0.82, green: 0.66, blue: 0.64)
        case .lilac: return Color(red: 0.68, green: 0.63, blue: 0.82)
        }
    }
    /// The swatch shown in the color picker.
    var swatch: Color { top }
    var isLight: Bool { self != .graphite && self != .black }
    var localizationKey: String { "color.\(rawValue)" }
}

/// A drawn mouse, top view, in a 100 × 140 design space.
enum MouseArtStyle: String, CaseIterable {
    /// Proportions taken from top-view product photos (no logos or text).
    case product
    /// Simple gradient body, wheel and seams only, like the 0.3 illustration.
    case classic
    /// Product-like shading with neutral details, no color accents.
    case clean
    /// Single-color outline, like a system symbol.
    case line
    /// The 0.5.0 drawing with colored accents.
    case detailed
}

struct MouseArt: View {
    let family: MouseShapeFamily
    var finish: MouseFinish = .graphite
    var style: MouseArtStyle = .product
    /// SUPERSTRIKE's separate button panel.
    var twoTone = false
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
        if family == .receiver && style != .product { drawReceiver(&context); return }
        switch style {
        case .product:
            switch family {
            case .ergoThumbRest: drawMXMaster(&context)
            case .esportsSymmetric: if twoTone { drawSuperstrike(&context) } else { drawEsportsProduct(&context) }
            case .compact: drawCompactProduct(&context)
            case .flatPebble: drawPebbleProduct(&context)
            case .vertical: drawVerticalProduct(&context)
            case .thumbTrackball: drawTrackballProduct(&context)
            case .esportsErgo: drawEsportsErgoProduct(&context)
            case .angular: drawAngularProduct(&context)
            case .sideGrid: drawSideGridProduct(&context)
            case .standardOval: drawOvalProduct(&context)
            case .receiver: drawReceiverProduct(&context)
            }
            return
        case .line: drawLine(&context); return
        case .classic: drawClassic(&context); return
        case .clean: drawClean(&context); return
        case .detailed: break
        }
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

    // MARK: Product drawings

    /// The finish, `amount` of the way from its top color (0) to its bottom color (1).
    /// Negative values lighten past the top color.
    private func tone(_ amount: CGFloat) -> Color {
        let top = NSColor(finish.top).usingColorSpace(.sRGB) ?? .gray
        let bottom = NSColor(finish.bottom).usingColorSpace(.sRGB) ?? .gray
        if amount < 0 { return Color(nsColor: top.blended(withFraction: -amount, of: .white) ?? top) }
        return Color(nsColor: top.blended(withFraction: min(amount, 1), of: bottom) ?? top)
    }

    /// Shell, rim light, soft top light and outline, shared by every family.
    private func shell(_ context: inout GraphicsContext, _ body: Path, light: CGPoint = CGPoint(x: 50, y: 40)) {
        contactShadow(&context, opacity: 0.26)
        context.fill(body, with: lin([tone(-0.04), tone(0.85)], CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 140)))
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.addFilter(.blur(radius: 4))
            layer.stroke(body, with: .color(.black.opacity(finish.isLight ? 0.10 : 0.30)), lineWidth: 7)
            layer.fill(Path(ellipseIn: CGRect(x: light.x - 22, y: light.y - 22, width: 44, height: 44)),
                       with: .color(.white.opacity(finish.isLight ? 0.40 : 0.08)))
        }
        context.stroke(body, with: .color(.black.opacity(finish.isLight ? 0.22 : 0.55)), lineWidth: 0.8)
    }

    private var seamColor: Color { .black.opacity(finish.isLight ? 0.22 : 0.65) }

    private func stroke(_ context: inout GraphicsContext, _ points: [CGPoint], width: CGFloat = 0.9, color: Color? = nil) {
        var p = Path(); p.addLines(points)
        context.stroke(p, with: .color(color ?? seamColor), lineWidth: width)
    }

    private func darkWheel(_ context: inout GraphicsContext, _ rect: CGRect) {
        context.fill(Path(roundedRect: rect.insetBy(dx: -1.4, dy: -1.4), cornerRadius: rect.width), with: .color(.black.opacity(0.85)))
        context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2),
                     with: lin([Color(white: 0.16), Color(white: 0.40), Color(white: 0.14)],
                               CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)))
        let ribs = Int(rect.height / 2.8)
        for i in 0..<ribs {
            context.fill(Path(CGRect(x: rect.minX + 0.8, y: rect.minY + 2 + CGFloat(i) * 2.8, width: rect.width - 1.6, height: 0.6)),
                         with: .color(.black.opacity(0.45)))
        }
    }

    private func pill(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
        context.fill(Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2), with: .color(color))
    }

    private var sideColor: Color { finish.isLight ? tone(0.55) : Color(white: 0.09) }

    private func led(_ context: inout GraphicsContext, _ point: CGPoint) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - 0.9, y: point.y - 0.9, width: 1.8, height: 1.8)),
                     with: .color(Color(red: 0.25, green: 0.9, blue: 0.4)))
    }

    /// MX Anywhere: rounded slab, metal wheel, shift button and status light.
    private func drawCompactProduct(_ context: inout GraphicsContext) {
        let body = Path(roundedRect: CGRect(x: 20, y: 6, width: 60, height: 128), cornerRadii: .init(topLeading: 26, bottomLeading: 30, bottomTrailing: 30, topTrailing: 26))
        shell(&context, body)
        stroke(&context, [CGPoint(x: 50, y: 7), CGPoint(x: 50, y: 52)])
        metalWheel(&context, CGRect(x: 46.2, y: 16, width: 7.6, height: 20))
        pill(&context, CGRect(x: 47, y: 40, width: 6, height: 10), sideColor)
        led(&context, CGPoint(x: 50, y: 56))
        pill(&context, CGRect(x: 18.5, y: 52, width: 3.4, height: 12), sideColor)
        pill(&context, CGRect(x: 18.5, y: 66, width: 3.4, height: 12), sideColor)
    }

    /// Pebble: a flat pill with a small wheel and one button behind it.
    private func drawPebbleProduct(_ context: inout GraphicsContext) {
        let body = Path(roundedRect: CGRect(x: 24, y: 12, width: 52, height: 116), cornerSize: CGSize(width: 26, height: 34))
        shell(&context, body, light: CGPoint(x: 50, y: 60))
        stroke(&context, [CGPoint(x: 50, y: 13), CGPoint(x: 50, y: 48)], width: 0.7)
        darkWheel(&context, CGRect(x: 46.8, y: 22, width: 6.4, height: 14))
        pill(&context, CGRect(x: 47.5, y: 40, width: 5, height: 7), tone(0.6))
    }

    /// Lift / MX Vertical seen from above: a leaning teardrop, buttons on the
    /// upper face, thumb buttons on the left and a textured grip below.
    private func drawVerticalProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 40, y: 8))
        body.addCurve(to: CGPoint(x: 86, y: 72), control1: CGPoint(x: 70, y: 4), control2: CGPoint(x: 88, y: 36))
        body.addCurve(to: CGPoint(x: 56, y: 136), control1: CGPoint(x: 86, y: 108), control2: CGPoint(x: 76, y: 134))
        body.addCurve(to: CGPoint(x: 16, y: 104), control1: CGPoint(x: 34, y: 138), control2: CGPoint(x: 16, y: 124))
        body.addCurve(to: CGPoint(x: 40, y: 8), control1: CGPoint(x: 15, y: 70), control2: CGPoint(x: 22, y: 12))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 56, y: 36))
        // Grip texture on the lower half.
        context.drawLayer { layer in
            layer.clip(to: body)
            for i in 0..<9 {
                var arc = Path()
                let y = 74 + CGFloat(i) * 6.5
                arc.move(to: CGPoint(x: 10, y: y)); arc.addQuadCurve(to: CGPoint(x: 92, y: y - 10), control: CGPoint(x: 50, y: y + 12))
                layer.stroke(arc, with: .color(.black.opacity(finish.isLight ? 0.06 : 0.22)), lineWidth: 0.8)
            }
        }
        // Button face: a raised ridge with the wheel.
        var ridge = Path()
        ridge.move(to: CGPoint(x: 36, y: 12)); ridge.addCurve(to: CGPoint(x: 34, y: 62), control1: CGPoint(x: 26, y: 26), control2: CGPoint(x: 26, y: 50))
        context.stroke(ridge, with: .color(seamColor), lineWidth: 0.9)
        stroke(&context, [CGPoint(x: 52, y: 10), CGPoint(x: 50, y: 50)])
        darkWheel(&context, CGRect(x: 47, y: 18, width: 7, height: 18))
        pill(&context, CGRect(x: 25, y: 36, width: 5, height: 10), sideColor)
        pill(&context, CGRect(x: 26, y: 48, width: 5, height: 10), sideColor)
    }

    /// MX Ergo / M575: a wide right-hand body with the ball under the thumb.
    private func drawTrackballProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 48, y: 4))
        body.addCurve(to: CGPoint(x: 92, y: 62), control1: CGPoint(x: 76, y: 2), control2: CGPoint(x: 94, y: 30))
        body.addCurve(to: CGPoint(x: 64, y: 136), control1: CGPoint(x: 90, y: 102), control2: CGPoint(x: 84, y: 130))
        body.addCurve(to: CGPoint(x: 26, y: 104), control1: CGPoint(x: 48, y: 140), control2: CGPoint(x: 34, y: 124))
        body.addCurve(to: CGPoint(x: 8, y: 52), control1: CGPoint(x: 18, y: 90), control2: CGPoint(x: 6, y: 72))
        body.addCurve(to: CGPoint(x: 48, y: 4), control1: CGPoint(x: 10, y: 26), control2: CGPoint(x: 26, y: 6))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 62, y: 44))
        stroke(&context, [CGPoint(x: 62, y: 6), CGPoint(x: 62, y: 50)])
        var seam = Path(); seam.move(to: CGPoint(x: 34, y: 52)); seam.addQuadCurve(to: CGPoint(x: 90, y: 50), control: CGPoint(x: 62, y: 58))
        context.stroke(seam, with: .color(seamColor), lineWidth: 0.9)
        darkWheel(&context, CGRect(x: 58.6, y: 16, width: 7, height: 18))
        pill(&context, CGRect(x: 40, y: 14, width: 5, height: 10), sideColor)
        pill(&context, CGRect(x: 40, y: 26, width: 5, height: 10), sideColor)
        let ball = CGRect(x: 8, y: 34, width: 30, height: 30)
        context.fill(Path(ellipseIn: ball.insetBy(dx: -2.2, dy: -2.2)), with: .color(.black.opacity(0.8)))
        context.fill(Path(ellipseIn: ball), with: .radialGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.45), Color(white: 0.25)]),
                                                                 center: CGPoint(x: ball.minX + 10, y: ball.minY + 9), startRadius: 1, endRadius: 24))
    }

    /// PRO / G305 / Superlight: the symmetric shell in one color.
    private func drawEsportsProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 50, y: 2))
        body.addCurve(to: CGPoint(x: 80, y: 16), control1: CGPoint(x: 66, y: 2), control2: CGPoint(x: 78, y: 6))
        body.addCurve(to: CGPoint(x: 80, y: 80), control1: CGPoint(x: 83, y: 34), control2: CGPoint(x: 79, y: 62))
        body.addCurve(to: CGPoint(x: 50, y: 138), control1: CGPoint(x: 83, y: 110), control2: CGPoint(x: 70, y: 138))
        body.addCurve(to: CGPoint(x: 20, y: 80), control1: CGPoint(x: 30, y: 138), control2: CGPoint(x: 17, y: 110))
        body.addCurve(to: CGPoint(x: 20, y: 16), control1: CGPoint(x: 21, y: 62), control2: CGPoint(x: 17, y: 34))
        body.addCurve(to: CGPoint(x: 50, y: 2), control1: CGPoint(x: 22, y: 6), control2: CGPoint(x: 34, y: 2))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 50, y: 82))
        stroke(&context, [CGPoint(x: 50, y: 3), CGPoint(x: 50, y: 58)])
        var seam = Path(); seam.move(to: CGPoint(x: 21, y: 56)); seam.addQuadCurve(to: CGPoint(x: 79, y: 56), control: CGPoint(x: 50, y: 64))
        context.stroke(seam, with: .color(seamColor), lineWidth: 0.9)
        darkWheel(&context, CGRect(x: 46.4, y: 14, width: 7.2, height: 20))
        pill(&context, CGRect(x: 18.2, y: 44, width: 3.2, height: 14), sideColor)
        pill(&context, CGRect(x: 18.6, y: 60, width: 3.2, height: 14), sideColor)
    }

    /// G703 / G903: longer, the main buttons split by side wings.
    private func drawEsportsErgoProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 48, y: 2))
        body.addCurve(to: CGPoint(x: 82, y: 22), control1: CGPoint(x: 66, y: 2), control2: CGPoint(x: 80, y: 8))
        body.addCurve(to: CGPoint(x: 84, y: 92), control1: CGPoint(x: 86, y: 46), control2: CGPoint(x: 86, y: 72))
        body.addCurve(to: CGPoint(x: 50, y: 138), control1: CGPoint(x: 84, y: 120), control2: CGPoint(x: 70, y: 138))
        body.addCurve(to: CGPoint(x: 18, y: 92), control1: CGPoint(x: 30, y: 138), control2: CGPoint(x: 17, y: 120))
        body.addCurve(to: CGPoint(x: 18, y: 22), control1: CGPoint(x: 15, y: 70), control2: CGPoint(x: 15, y: 44))
        body.addCurve(to: CGPoint(x: 48, y: 2), control1: CGPoint(x: 20, y: 8), control2: CGPoint(x: 32, y: 2))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 50, y: 88))
        stroke(&context, [CGPoint(x: 50, y: 3), CGPoint(x: 50, y: 62)])
        // Side wings that run beside the main buttons.
        stroke(&context, [CGPoint(x: 30, y: 8), CGPoint(x: 34, y: 40), CGPoint(x: 28, y: 66)])
        stroke(&context, [CGPoint(x: 70, y: 8), CGPoint(x: 66, y: 40), CGPoint(x: 72, y: 66)])
        darkWheel(&context, CGRect(x: 46.4, y: 14, width: 7.2, height: 20))
        pill(&context, CGRect(x: 47.5, y: 38, width: 5, height: 7), sideColor)
        pill(&context, CGRect(x: 16.2, y: 48, width: 3.2, height: 13), sideColor)
        pill(&context, CGRect(x: 16.6, y: 63, width: 3.2, height: 13), sideColor)
    }

    /// G502: angular shell, thumb wing, two extra buttons left of the left click.
    private func drawAngularProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 34, y: 4))
        body.addLine(to: CGPoint(x: 68, y: 4))
        body.addQuadCurve(to: CGPoint(x: 82, y: 22), control: CGPoint(x: 80, y: 6))
        body.addLine(to: CGPoint(x: 80, y: 70))
        body.addQuadCurve(to: CGPoint(x: 86, y: 104), control: CGPoint(x: 86, y: 86))
        body.addQuadCurve(to: CGPoint(x: 52, y: 138), control: CGPoint(x: 84, y: 136))
        body.addQuadCurve(to: CGPoint(x: 22, y: 116), control: CGPoint(x: 30, y: 138))
        body.addLine(to: CGPoint(x: 6, y: 92))
        body.addQuadCurve(to: CGPoint(x: 16, y: 66), control: CGPoint(x: 4, y: 74))
        body.addLine(to: CGPoint(x: 20, y: 24))
        body.addQuadCurve(to: CGPoint(x: 34, y: 4), control: CGPoint(x: 20, y: 6))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 54, y: 90))
        stroke(&context, [CGPoint(x: 52, y: 5), CGPoint(x: 52, y: 60)])
        stroke(&context, [CGPoint(x: 22, y: 64), CGPoint(x: 40, y: 64), CGPoint(x: 52, y: 60), CGPoint(x: 80, y: 64)])
        stroke(&context, [CGPoint(x: 18, y: 68), CGPoint(x: 26, y: 112)])
        metalWheel(&context, CGRect(x: 48.2, y: 14, width: 7.6, height: 20))
        pill(&context, CGRect(x: 26, y: 12, width: 6, height: 12), sideColor)
        pill(&context, CGRect(x: 26, y: 27, width: 6, height: 10), sideColor)
        pill(&context, CGRect(x: 49, y: 38, width: 6, height: 6), sideColor)
        pill(&context, CGRect(x: 15, y: 70, width: 4, height: 11), sideColor)
        pill(&context, CGRect(x: 15.6, y: 83, width: 4, height: 11), sideColor)
        // Light strip along the right rear edge.
        var strip = Path(); strip.move(to: CGPoint(x: 62, y: 120)); strip.addQuadCurve(to: CGPoint(x: 82, y: 100), control: CGPoint(x: 78, y: 118))
        context.stroke(strip, with: .linearGradient(Gradient(colors: [.purple.opacity(0.8), .cyan.opacity(0.8)]), startPoint: CGPoint(x: 62, y: 120), endPoint: CGPoint(x: 82, y: 100)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    /// G600: right-hand body with the twelve-button thumb grid.
    private func drawSideGridProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 48, y: 4))
        body.addCurve(to: CGPoint(x: 86, y: 58), control1: CGPoint(x: 72, y: 4), control2: CGPoint(x: 88, y: 28))
        body.addCurve(to: CGPoint(x: 66, y: 136), control1: CGPoint(x: 84, y: 98), control2: CGPoint(x: 82, y: 128))
        body.addCurve(to: CGPoint(x: 12, y: 112), control1: CGPoint(x: 46, y: 140), control2: CGPoint(x: 16, y: 134))
        body.addCurve(to: CGPoint(x: 48, y: 4), control1: CGPoint(x: 6, y: 66), control2: CGPoint(x: 22, y: 4))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 58, y: 84))
        stroke(&context, [CGPoint(x: 50, y: 5), CGPoint(x: 50, y: 56)])
        var seam = Path(); seam.move(to: CGPoint(x: 18, y: 58)); seam.addQuadCurve(to: CGPoint(x: 84, y: 58), control: CGPoint(x: 50, y: 66))
        context.stroke(seam, with: .color(seamColor), lineWidth: 0.9)
        darkWheel(&context, CGRect(x: 46.4, y: 14, width: 7.2, height: 20))
        for row in 0..<4 { for col in 0..<3 {
            context.fill(Path(roundedRect: CGRect(x: 12 + CGFloat(col) * 5.6, y: 64 + CGFloat(row) * 7.2, width: 4.6, height: 6), cornerRadius: 1.2),
                         with: .color(sideColor))
        } }
    }

    /// Office mice (M185, M325, B100): an egg wider at the rear, with grips.
    private func drawOvalProduct(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 50, y: 6))
        body.addCurve(to: CGPoint(x: 80, y: 56), control1: CGPoint(x: 70, y: 6), control2: CGPoint(x: 80, y: 28))
        body.addCurve(to: CGPoint(x: 50, y: 136), control1: CGPoint(x: 82, y: 104), control2: CGPoint(x: 72, y: 136))
        body.addCurve(to: CGPoint(x: 20, y: 56), control1: CGPoint(x: 28, y: 136), control2: CGPoint(x: 18, y: 104))
        body.addCurve(to: CGPoint(x: 50, y: 6), control1: CGPoint(x: 20, y: 28), control2: CGPoint(x: 30, y: 6))
        body.closeSubpath()
        shell(&context, body, light: CGPoint(x: 50, y: 80))
        // Side grips.
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.addFilter(.blur(radius: 2.5))
            layer.fill(Path(ellipseIn: CGRect(x: 4, y: 60, width: 20, height: 64)), with: .color(.black.opacity(finish.isLight ? 0.10 : 0.24)))
            layer.fill(Path(ellipseIn: CGRect(x: 76, y: 60, width: 20, height: 64)), with: .color(.black.opacity(finish.isLight ? 0.10 : 0.24)))
        }
        stroke(&context, [CGPoint(x: 50, y: 7), CGPoint(x: 50, y: 54)])
        darkWheel(&context, CGRect(x: 46.6, y: 18, width: 6.8, height: 18))
        led(&context, CGPoint(x: 50, y: 44))
    }

    /// A receiver dongle, front view.
    private func drawReceiverProduct(_ context: inout GraphicsContext) {
        contactShadow(&context, opacity: 0.2)
        let body = Path(roundedRect: CGRect(x: 34, y: 34, width: 32, height: 56), cornerRadius: 9)
        context.fill(body, with: lin([Color(white: 0.24), Color(white: 0.08)], CGPoint(x: 50, y: 34), CGPoint(x: 50, y: 90)))
        context.stroke(body, with: .color(.white.opacity(0.12)), lineWidth: 0.8)
        let plug = Path(roundedRect: CGRect(x: 39, y: 90, width: 22, height: 24), cornerRadius: 1.6)
        context.fill(plug, with: lin([Color(white: 0.88), Color(white: 0.6)], CGPoint(x: 39, y: 90), CGPoint(x: 61, y: 114)))
        context.fill(Path(CGRect(x: 43, y: 98, width: 4, height: 3)), with: .color(Color(white: 0.35)))
        context.fill(Path(CGRect(x: 53, y: 98, width: 4, height: 3)), with: .color(Color(white: 0.35)))
    }

    private func lin(_ colors: [Color], _ from: CGPoint, _ to: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
    }

    private func metalWheel(_ context: inout GraphicsContext, _ rect: CGRect, ribs: Int = 9) {
        context.fill(Path(roundedRect: rect.insetBy(dx: -1.4, dy: -1.4), cornerRadius: 3), with: .color(.black.opacity(0.85)))
        context.fill(Path(roundedRect: rect, cornerRadius: 2.4),
                     with: lin([Color(white: 0.55), Color(white: 0.92), Color(white: 0.62), Color(white: 0.35)],
                               CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)))
        for i in 0..<ribs {
            let y = rect.minY + 1.6 + CGFloat(i) * (rect.height - 3.2) / CGFloat(max(ribs - 1, 1))
            context.fill(Path(CGRect(x: rect.minX + 0.6, y: y - 0.35, width: rect.width - 1.2, height: 0.7)), with: .color(.black.opacity(0.28)))
        }
    }

    /// MX Master 4: square button block, straight left edge, thumb shelf
    /// jutting out mid-body, wide metal wheel, shift button and status light.
    private func drawMXMaster(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 30.7, y: 4))
        body.addQuadCurve(to: CGPoint(x: 36, y: 0.2), control: CGPoint(x: 30.9, y: 0.4))
        body.addCurve(to: CGPoint(x: 86, y: 6.6), control1: CGPoint(x: 55, y: 0), control2: CGPoint(x: 74, y: 2))
        body.addQuadCurve(to: CGPoint(x: 94, y: 14), control: CGPoint(x: 93, y: 8.5))
        body.addLine(to: CGPoint(x: 96.2, y: 45))
        body.addCurve(to: CGPoint(x: 99.4, y: 100), control1: CGPoint(x: 99.5, y: 62), control2: CGPoint(x: 100, y: 84))
        body.addCurve(to: CGPoint(x: 56, y: 140), control1: CGPoint(x: 98.5, y: 124), control2: CGPoint(x: 82, y: 140))
        body.addCurve(to: CGPoint(x: 22, y: 122), control1: CGPoint(x: 42, y: 140), control2: CGPoint(x: 30, y: 133))
        body.addCurve(to: CGPoint(x: 0.4, y: 80), control1: CGPoint(x: 12, y: 110), control2: CGPoint(x: 1, y: 96))
        body.addCurve(to: CGPoint(x: 15, y: 53.6), control1: CGPoint(x: 0, y: 66), control2: CGPoint(x: 4, y: 56))
        body.addQuadCurve(to: CGPoint(x: 30.7, y: 51), control: CGPoint(x: 24, y: 51.5))
        body.closeSubpath()

        contactShadow(&context, opacity: 0.28)
        // Palm.
        context.fill(body, with: lin([tone(0.25), tone(0.05)],
                                     CGPoint(x: 50, y: 40), CGPoint(x: 50, y: 140)))
        // Button block (lighter graphite), clipped to the body.
        var buttons = Path()
        buttons.move(to: CGPoint(x: 28, y: 0)); buttons.addLine(to: CGPoint(x: 100, y: 0)); buttons.addLine(to: CGPoint(x: 100, y: 44))
        buttons.addQuadCurve(to: CGPoint(x: 30.7, y: 51.5), control: CGPoint(x: 62, y: 46))
        buttons.closeSubpath()
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(buttons, with: lin([tone(-0.06), tone(0.12)],
                                          CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)))
            // Thumb pad: a lighter recessed panel on the shelf.
            var pad = Path()
            pad.move(to: CGPoint(x: 7, y: 61)); pad.addCurve(to: CGPoint(x: 23, y: 117), control1: CGPoint(x: 2, y: 84), control2: CGPoint(x: 11, y: 106))
            pad.addCurve(to: CGPoint(x: 25.5, y: 60), control1: CGPoint(x: 27, y: 100), control2: CGPoint(x: 28, y: 76))
            pad.closeSubpath()
            layer.fill(pad, with: lin([tone(0.18), tone(0.32)],
                                      CGPoint(x: 8, y: 60), CGPoint(x: 26, y: 118)))
            layer.stroke(pad, with: .color(.black.opacity(0.45)), lineWidth: 0.7)
            // Right rim light and soft top light.
            var rim = Path(); rim.move(to: CGPoint(x: 97, y: 50)); rim.addCurve(to: CGPoint(x: 90, y: 124), control1: CGPoint(x: 100, y: 80), control2: CGPoint(x: 99, y: 108))
            layer.stroke(rim, with: .color(.white.opacity(0.10)), lineWidth: 2.5)
        }
        context.stroke(body, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
        // Button split and the seam to the palm.
        var split = Path(); split.move(to: CGPoint(x: 60.6, y: 0.6)); split.addLine(to: CGPoint(x: 60.6, y: 46))
        context.stroke(split, with: .color(.black.opacity(0.7)), lineWidth: 0.9)
        var seam = Path(); seam.move(to: CGPoint(x: 30.7, y: 51.5)); seam.addQuadCurve(to: CGPoint(x: 96.2, y: 44.5), control: CGPoint(x: 62, y: 46))
        context.stroke(seam, with: .color(.black.opacity(0.75)), lineWidth: 0.9)
        metalWheel(&context, CGRect(x: 56.4, y: 19, width: 8.6, height: 23))
        // Shift button and status light.
        context.fill(Path(roundedRect: CGRect(x: 57, y: 54.5, width: 7, height: 9), cornerRadius: 1.6), with: .color(Color(white: 0.12)))
        context.stroke(Path(roundedRect: CGRect(x: 57, y: 54.5, width: 7, height: 9), cornerRadius: 1.6), with: .color(.white.opacity(0.12)), lineWidth: 0.5)
        context.fill(Path(ellipseIn: CGRect(x: 59.6, y: 67, width: 1.8, height: 1.8)), with: .color(Color(red: 0.25, green: 0.9, blue: 0.4)))
        // Thumb wheel and the two side buttons on the shelf edge.
        metalWheel(&context, CGRect(x: 26.6, y: 58.5, width: 5.6, height: 19), ribs: 7)
        context.fill(Path(roundedRect: CGRect(x: 27.4, y: 79, width: 4, height: 7), cornerRadius: 1.4), with: .color(Color(white: 0.30)))
    }

    /// PRO X2 SUPERSTRIKE: long symmetric egg, a separate dark button panel with
    /// a straight rear edge, two left side buttons.
    private func drawSuperstrike(_ context: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 50, y: 0))
        body.addCurve(to: CGPoint(x: 82.5, y: 13), control1: CGPoint(x: 68, y: 0), control2: CGPoint(x: 81, y: 3))
        body.addCurve(to: CGPoint(x: 81.5, y: 79), control1: CGPoint(x: 85, y: 30), control2: CGPoint(x: 81, y: 60))
        body.addCurve(to: CGPoint(x: 83, y: 108), control1: CGPoint(x: 82, y: 90), control2: CGPoint(x: 83.6, y: 99))
        body.addCurve(to: CGPoint(x: 50, y: 140), control1: CGPoint(x: 82, y: 128), control2: CGPoint(x: 68, y: 140))
        body.addCurve(to: CGPoint(x: 17, y: 108), control1: CGPoint(x: 32, y: 140), control2: CGPoint(x: 18, y: 128))
        body.addCurve(to: CGPoint(x: 18.5, y: 79), control1: CGPoint(x: 16.4, y: 99), control2: CGPoint(x: 18, y: 90))
        body.addCurve(to: CGPoint(x: 17.5, y: 13), control1: CGPoint(x: 19, y: 60), control2: CGPoint(x: 15, y: 30))
        body.addCurve(to: CGPoint(x: 50, y: 0), control1: CGPoint(x: 19, y: 3), control2: CGPoint(x: 32, y: 0))
        body.closeSubpath()

        let shellLight = [tone(-0.05), tone(0.7)]
        contactShadow(&context, opacity: 0.26)
        context.fill(body, with: lin(shellLight, CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 140)))
        context.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 62)),
                       with: lin([Color(white: 0.16), Color(white: 0.06)], CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 62)))
            layer.addFilter(.blur(radius: 3))
            layer.fill(Path(ellipseIn: CGRect(x: 30, y: 74, width: 40, height: 40)), with: .color(.white.opacity(finish == .black ? 0.06 : 0.35)))
        }
        context.stroke(body, with: .color(.black.opacity(finish == .black ? 0.6 : 0.25)), lineWidth: 0.8)
        var split = Path(); split.move(to: CGPoint(x: 50, y: 0.5)); split.addLine(to: CGPoint(x: 50, y: 62))
        context.stroke(split, with: .color(.white.opacity(0.10)), lineWidth: 0.8)
        var rear = Path(); rear.move(to: CGPoint(x: 17, y: 62)); rear.addLine(to: CGPoint(x: 83, y: 62))
        context.stroke(rear, with: .color(.black.opacity(0.55)), lineWidth: 0.9)
        // Wheel in a dark well.
        context.fill(Path(roundedRect: CGRect(x: 44.6, y: 14, width: 10.8, height: 26), cornerRadius: 5), with: .color(.black))
        context.fill(Path(roundedRect: CGRect(x: 46.2, y: 16, width: 7.6, height: 22), cornerRadius: 3.8),
                     with: lin([Color(white: 0.20), Color(white: 0.42), Color(white: 0.18)], CGPoint(x: 46, y: 27), CGPoint(x: 54, y: 27)))
        for i in 0..<7 {
            context.fill(Path(CGRect(x: 47, y: 18.5 + CGFloat(i) * 2.8, width: 6, height: 0.6)), with: .color(.black.opacity(0.4)))
        }
        // Side buttons on the left edge.
        let side = finish == .black ? Color(white: 0.20) : Color(white: 0.86)
        for rect in [CGRect(x: 15.6, y: 44, width: 3.4, height: 18), CGRect(x: 16.2, y: 64, width: 3.4, height: 18)] {
            context.fill(Path(roundedRect: rect, cornerRadius: 1.6), with: .color(side))
            context.stroke(Path(roundedRect: rect, cornerRadius: 1.6), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        }
        context.fill(Path(ellipseIn: CGRect(x: 49.1, y: 70, width: 1.8, height: 1.8)), with: .color(Color(red: 0.25, green: 0.9, blue: 0.4)))
    }

    // MARK: Styles

    private func contactShadow(_ context: inout GraphicsContext, opacity: Double) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.fill(Path(ellipseIn: CGRect(x: 16, y: 118, width: 68, height: 16)), with: .color(.black.opacity(opacity)))
        }
    }

    private func drawWheel(_ context: inout GraphicsContext, fill: Color) {
        let wheel = wheelCenter
        let rect = CGRect(x: wheel.x - 4, y: wheel.y - 10, width: 8, height: 20)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(fill))
        for i in 0..<6 {
            let y = rect.minY + 3 + CGFloat(i) * 2.8
            context.fill(Path(CGRect(x: rect.minX + 1.5, y: y, width: rect.width - 3, height: 0.8)), with: .color(.white.opacity(0.22)))
        }
    }

    private func drawSeams(_ context: inout GraphicsContext, color: Color, width: CGFloat) {
        let wheel = wheelCenter
        var split = Path()
        split.move(to: CGPoint(x: wheel.x, y: wheel.y + 10))
        split.addLine(to: CGPoint(x: wheel.x, y: splitBottom))
        var top = Path()
        top.move(to: CGPoint(x: wheel.x, y: wheel.y - 10))
        top.addLine(to: CGPoint(x: wheel.x, y: wheel.y - 18))
        var seam = Path()
        seam.move(to: CGPoint(x: 26, y: splitBottom + 4))
        seam.addQuadCurve(to: CGPoint(x: 76, y: splitBottom + 4), control: CGPoint(x: 51, y: splitBottom + 13))
        for path in [split, top, seam] { context.stroke(path, with: .color(color), lineWidth: width) }
    }

    /// The 0.3 look: soft gradient, wheel, seams. No feature details.
    private func drawClassic(_ context: inout GraphicsContext) {
        let body = bodyPath
        contactShadow(&context, opacity: 0.16)
        let colors = finish.isLight ? [Color(white: 0.99), Color(white: 0.80)] : [Color(white: 0.38), Color(white: 0.16)]
        context.fill(body, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 20, y: 0), endPoint: CGPoint(x: 80, y: 140)))
        context.stroke(body, with: .color(.white.opacity(0.25)), lineWidth: 1)
        drawSeams(&context, color: .black.opacity(0.2), width: 0.9)
        drawWheel(&context, fill: Color(white: 0.12))
    }

    /// Product-like: matte body, rim light, darker edges, neutral details.
    private func drawClean(_ context: inout GraphicsContext) {
        let body = bodyPath
        contactShadow(&context, opacity: 0.25)
        context.fill(body, with: .linearGradient(Gradient(colors: [finish.top, finish.bottom]),
                                                 startPoint: CGPoint(x: 50, y: 0), endPoint: CGPoint(x: 50, y: 140)))
        context.drawLayer { layer in
            layer.clip(to: body)
            // Edge falloff and a broad soft top light.
            layer.addFilter(.blur(radius: 3))
            layer.stroke(body, with: .color(.black.opacity(finish.isLight ? 0.08 : 0.22)), lineWidth: 6)
            layer.fill(Path(ellipseIn: CGRect(x: 26, y: 4, width: 48, height: 60)), with: .color(.white.opacity(finish.isLight ? 0.45 : 0.12)))
        }
        context.stroke(body, with: .color(.white.opacity(finish.isLight ? 0.6 : 0.10)), lineWidth: 0.8)
        drawSeams(&context, color: finish.isLight ? .black.opacity(0.18) : .black.opacity(0.45), width: 0.8)
        drawWheel(&context, fill: Color(white: finish.isLight ? 0.30 : 0.10))
        let neutral = finish.isLight ? Color.black.opacity(0.25) : Color.black.opacity(0.45)
        switch family {
        case .ergoThumbRest:
            sideButtonColor(&context, CGRect(x: 15, y: 58, width: 7, height: 8), neutral)
            sideButtonColor(&context, CGRect(x: 15, y: 68, width: 7, height: 8), neutral)
        case .compact, .esportsSymmetric, .esportsErgo, .vertical:
            sideButtonColor(&context, CGRect(x: 20, y: 58, width: 4, height: 10), neutral)
            sideButtonColor(&context, CGRect(x: 20, y: 70, width: 4, height: 10), neutral)
        case .thumbTrackball:
            let ball = CGRect(x: 15, y: 71, width: 28, height: 28)
            context.fill(Path(ellipseIn: ball), with: .radialGradient(Gradient(colors: [Color(white: 0.75), Color(white: 0.35)]),
                                                                   center: CGPoint(x: ball.minX + 9, y: ball.minY + 8), startRadius: 1, endRadius: 22))
        default:
            break
        }
    }

    /// One color, outlines only.
    private func drawLine(_ context: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.foreground
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        context.stroke(bodyPath, with: ink, style: style)
        let wheel = wheelCenter
        context.stroke(Path(roundedRect: CGRect(x: wheel.x - 4, y: wheel.y - 9, width: 8, height: 18), cornerRadius: 4), with: ink, style: StrokeStyle(lineWidth: 3.2))
        var split = Path()
        split.move(to: CGPoint(x: wheel.x, y: wheel.y + 9)); split.addLine(to: CGPoint(x: wheel.x, y: splitBottom))
        context.stroke(split, with: ink, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        if family == .thumbTrackball {
            context.stroke(Path(ellipseIn: CGRect(x: 17, y: 73, width: 24, height: 24)), with: ink, style: StrokeStyle(lineWidth: 3.2))
        }
    }

    private func sideButtonColor(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
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
