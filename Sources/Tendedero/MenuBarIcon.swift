import AppKit

/// A small template drawing: one photo clipped to a gently sagging line.
/// AppKit rasterizes it at the menu bar's backing scale and supplies the tint.
enum MenuBarIcon {
    static let size = NSSize(width: 20, height: 18)

    static func image(clipboardEnabled: Bool, description: String) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, clipboardEnabled: clipboardEnabled)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    static func draw(in context: CGContext, clipboardEnabled: Bool) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(1.35)

        context.move(to: CGPoint(x: 2, y: 15))
        context.addQuadCurve(to: CGPoint(x: 18, y: 15), control: CGPoint(x: 10, y: 12.5))
        context.strokePath()

        let frame = CGPath(roundedRect: CGRect(x: 5, y: 2.5, width: 10, height: 8.5),
                           cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
        context.addPath(frame)
        if clipboardEnabled { context.fillPath() } else { context.strokePath() }

        // One small landscape stroke reads as a photo without adding detail.
        if clipboardEnabled { context.setBlendMode(.clear) }
        context.setLineWidth(1.1)
        context.move(to: CGPoint(x: 6.8, y: 4.4))
        context.addLine(to: CGPoint(x: 9.4, y: 7))
        context.addLine(to: CGPoint(x: 13.2, y: 4.4))
        context.strokePath()
        context.setBlendMode(.normal)

        context.addPath(CGPath(roundedRect: CGRect(x: 9.15, y: 10.35, width: 1.7, height: 4.3),
                               cornerWidth: 0.85, cornerHeight: 0.85, transform: nil))
        context.fillPath()
    }
}
