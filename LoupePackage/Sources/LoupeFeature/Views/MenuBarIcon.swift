import AppKit

/// Loupe's menu bar glyph: the lens seen head on, drawn as a template image so
/// it follows the menu bar's colour. When a note needs the person, a gap opens
/// in the top-right corner for the coral dot that `StatusDotView` draws there.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)
    /// Where the coral dot sits, in the glyph's top-left-origin coordinates
    static let dotCenter = CGPoint(x: 14.6, y: 3.4)
    static let dotRadius: CGFloat = 3.1
    static let gapRadius: CGFloat = 4.4

    static func image(leavingRoomForDot: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { bounds in
            if leavingRoomForDot {
                let clip = NSBezierPath(rect: bounds)
                clip.append(NSBezierPath(ovalIn: circleRect(center: dotCenter, radius: gapRadius)))
                clip.windingRule = .evenOdd
                clip.addClip()
            }
            NSColor.black.set()
            let ring = NSBezierPath(ovalIn: circleRect(center: CGPoint(x: 9, y: 9), radius: 6.9))
            ring.lineWidth = 2.2
            ring.stroke()

            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: circleRect(center: CGPoint(x: 9, y: 9), radius: 3.1)).fill()

            // Glint on the glass, tilted towards the top left
            NSColor.black.setFill()
            let glint = NSBezierPath(ovalIn: NSRect(x: -1.5, y: -1.1, width: 3, height: 2.2))
            var transform = AffineTransform(translationByX: 6.9, byY: 6.9)
            transform.rotate(byDegrees: -45)
            glint.transform(using: transform)
            glint.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func circleRect(center: CGPoint, radius: CGFloat) -> NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// The coral dot laid over the menu bar glyph. It's a separate view because a
/// template image can only be one colour.
final class StatusDotView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 1, green: 0x5B / 255.0, blue: 0x3A / 255.0, alpha: 1).cgColor
        layer?.cornerRadius = frame.width / 2
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
