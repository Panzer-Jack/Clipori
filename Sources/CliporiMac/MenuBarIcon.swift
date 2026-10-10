import AppKit

/// A small optical variant of the Clipori cat, rendered at the display's native scale.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            let head = NSBezierPath()
            head.move(to: NSPoint(x: 2, y: 9))
            head.line(to: NSPoint(x: 1.4, y: 16.2))
            head.line(to: NSPoint(x: 6, y: 13.3))
            head.curve(to: NSPoint(x: 11.7, y: 13.3), controlPoint1: NSPoint(x: 7.7, y: 14.1), controlPoint2: NSPoint(x: 10, y: 14.1))
            head.line(to: NSPoint(x: 16.6, y: 16.2))
            head.line(to: NSPoint(x: 16, y: 9))
            head.curve(to: NSPoint(x: 9, y: 2), controlPoint1: NSPoint(x: 18.6, y: 3.4), controlPoint2: NSPoint(x: 13.6, y: 2))
            head.curve(to: NSPoint(x: 2, y: 9), controlPoint1: NSPoint(x: 4.2, y: 2), controlPoint2: NSPoint(x: -0.5, y: 3.9))
            head.close()
            NSColor.black.setFill()
            head.fill()

            // Transparent facial features remain visible when macOS tints the template.
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            for x in [5.1, 11.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 7.5, width: 1.4, height: 2.5), xRadius: 0.7, yRadius: 0.7).fill()
            }
            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 7.3, y: 6.1))
            smile.curve(to: NSPoint(x: 10.7, y: 6.1), controlPoint1: NSPoint(x: 8, y: 4.5), controlPoint2: NSPoint(x: 10, y: 4.5))
            smile.lineWidth = 1.1
            smile.lineCapStyle = .round
            smile.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipori"
        return image
    }()
}
