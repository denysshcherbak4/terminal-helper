import AppKit

func terminalGlyph(size: CGFloat, appIcon: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = size / 32
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    if appIcon {
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 30, height: 30), xRadius: 7, yRadius: 7).fill()
        NSColor.white.setStroke()
    } else { NSColor.black.setStroke() }
    let outline = NSBezierPath(roundedRect: NSRect(x: 4, y: 7, width: 24, height: 18), xRadius: 4, yRadius: 4)
    outline.lineWidth = 2; outline.stroke()
    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 9, y: 20)); prompt.line(to: NSPoint(x: 13, y: 16)); prompt.line(to: NSPoint(x: 9, y: 12))
    prompt.lineWidth = 2; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round; prompt.stroke()
    let underscore = NSBezierPath()
    underscore.move(to: NSPoint(x: 16, y: 12)); underscore.line(to: NSPoint(x: 20, y: 12))
    underscore.lineWidth = 2; underscore.lineCapStyle = .round; underscore.stroke()
    let suggestion = NSBezierPath()
    suggestion.move(to: NSPoint(x: 22, y: 16)); suggestion.line(to: NSPoint(x: 25, y: 16))
    suggestion.lineWidth = 1.5; suggestion.lineCapStyle = .round; suggestion.stroke()
    image.unlockFocus()
    image.isTemplate = !appIcon
    return image
}
