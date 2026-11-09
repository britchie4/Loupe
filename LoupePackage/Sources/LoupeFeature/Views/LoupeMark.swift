import SwiftUI

/// Loupe's mark without the app icon's background: the jeweler's loupe seen from
/// above, with a coral rim around the lens. Drawn from the same shapes as the app
/// icon layers in `Loupe/AppIcon.icon`, so it stays crisp at any size.
struct LoupeMark: View {
    /// Width to height of the drawing (the mark spans 56 x 46 units)
    static let aspectRatio: CGFloat = 56.0 / 46.0

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 56, size.height / 46)
            context.translateBy(x: (size.width - 56 * scale) / 2, y: (size.height - 46 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            // Work in the icon's own units: the mark runs from x 22 to 78 and y 28 to 74
            context.translateBy(x: -22, y: -28)

            // Barrel: a shaded cylinder band with a ridged grip
            var barrel = Path()
            barrel.move(to: CGPoint(x: 22, y: 44))
            barrel.addLine(to: CGPoint(x: 22, y: 58))
            barrel.addArc(ellipseCenter: CGPoint(x: 50, y: 58), radii: CGSize(width: 28, height: 16), from: .pi, to: 0, clockwise: true)
            barrel.addLine(to: CGPoint(x: 78, y: 44))
            barrel.closeSubpath()
            context.fill(barrel, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(hex: "#23262e"), location: 0),
                    .init(color: Color(hex: "#9aa0ab"), location: 0.32),
                    .init(color: Color(hex: "#6b717e"), location: 0.55),
                    .init(color: Color(hex: "#23262e"), location: 1)
                ]),
                startPoint: CGPoint(x: 22, y: 0), endPoint: CGPoint(x: 78, y: 0)))
            if scale * 56 >= 28 {
                var ridges = Path()
                for i in 1..<17 {
                    let x = 50 - 28 * cos(Double.pi * Double(i) / 17)
                    ridges.move(to: CGPoint(x: x, y: 52))
                    ridges.addLine(to: CGPoint(x: x, y: 66))
                }
                context.drawLayer { layer in
                    layer.clip(to: barrel)
                    layer.stroke(ridges, with: .color(.black.opacity(0.32)), lineWidth: 1.3)
                }
            }

            // Coral rim
            let rim = Path(ellipseIn: CGRect(x: 22, y: 28, width: 56, height: 32))
            context.fill(rim, with: .linearGradient(
                Gradient(colors: [Color(hex: "#ff8466"), Color(hex: "#ff5b3a")]),
                startPoint: CGPoint(x: 0, y: 28), endPoint: CGPoint(x: 0, y: 60)))

            // Glass and its glint
            let glassRect = CGRect(x: 27.5, y: 31.143, width: 45, height: 25.714)
            context.fill(Path(ellipseIn: glassRect), with: .radialGradient(
                Gradient(colors: [Color(hex: "#3a4152"), Color(hex: "#0f1218")]),
                center: CGPoint(x: 27.5 + 45 * 0.36, y: 31.143 + 25.714 * 0.3), startRadius: 0, endRadius: 40))
            var glint = Path()
            glint.addArc(ellipseCenter: CGPoint(x: 50, y: 44), radii: CGSize(width: 17.55, height: 10.03),
                         from: .pi * 1.03, to: .pi * 1.47, clockwise: false)
            context.stroke(glint, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private extension Path {
    /// Adds an arc of an axis-aligned ellipse, sweeping between two angles in radians
    mutating func addArc(ellipseCenter c: CGPoint, radii r: CGSize, from start: Double, to end: Double, clockwise: Bool) {
        let steps = 48
        var sweep = end - start
        if clockwise, sweep > 0 { sweep -= 2 * .pi }
        if !clockwise, sweep < 0 { sweep += 2 * .pi }
        for i in 0...steps {
            let a = start + sweep * Double(i) / Double(steps)
            let p = CGPoint(x: c.x + r.width * cos(a), y: c.y + r.height * sin(a))
            if i == 0, isEmpty { move(to: p) } else { addLine(to: p) }
        }
    }
}

#if DEBUG
#Preview {
    LoupeMark().frame(width: 120).padding()
}
#endif
