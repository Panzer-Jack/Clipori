import AppKit

// One drawing exports the Finder icon, iOS asset, and README brand mark.
// swift scripts/make-icon.swift Resources/AppIcon.icns Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png docs/assets/clipori-icon.png
guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: make-icon.swift output.icns [ios.png] [brand.png]\n", stderr)
    exit(1)
}
let output = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("Clipori.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: Int, mobile: Bool = false) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
    if mobile { NSColor(red: 0.55, green: 0.46, blue: 0.91, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill() }
    let tile = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 215, yRadius: 215)
    NSGradient(starting: NSColor(red: 0.77, green: 0.65, blue: 1, alpha: 1), ending: NSColor(red: 0.44, green: 0.40, blue: 0.83, alpha: 1))!.draw(in: tile, angle: -75)
    NSColor(white: 1, alpha: 0.17).setStroke(); tile.lineWidth = 3; tile.stroke()
    let cat = NSBezierPath()
    cat.move(to: NSPoint(x: 260, y: 500))
    cat.line(to: NSPoint(x: 234, y: 795))
    cat.line(to: NSPoint(x: 427, y: 671))
    cat.curve(to: NSPoint(x: 600, y: 671), controlPoint1: NSPoint(x: 474, y: 697), controlPoint2: NSPoint(x: 552, y: 697))
    cat.line(to: NSPoint(x: 791, y: 795)); cat.line(to: NSPoint(x: 762, y: 500))
    cat.curve(to: NSPoint(x: 512, y: 248), controlPoint1: NSPoint(x: 870, y: 297), controlPoint2: NSPoint(x: 678, y: 244))
    cat.curve(to: NSPoint(x: 260, y: 500), controlPoint1: NSPoint(x: 323, y: 244), controlPoint2: NSPoint(x: 161, y: 317))
    cat.close()
    NSColor(red: 0.98, green: 0.95, blue: 1, alpha: 1).setFill(); cat.fill()
    NSColor(red: 0.32, green: 0.25, blue: 0.49, alpha: 1).setFill()
    for x in [404.0, 596.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 450, width: 26, height: 76), xRadius: 13, yRadius: 13).fill() }
    let smile = NSBezierPath(); smile.move(to: NSPoint(x: 472, y: 419))
    smile.curve(to: NSPoint(x: 552, y: 419), controlPoint1: NSPoint(x: 487, y: 377), controlPoint2: NSPoint(x: 537, y: 377))
    smile.lineWidth = 16; smile.lineCapStyle = .round; NSColor(red: 0.38, green: 0.29, blue: 0.52, alpha: 1).setStroke(); smile.stroke()
    NSColor(red: 0.98, green: 0.60, blue: 0.77, alpha: 0.78).setFill()
    for x in [310.0, 644.0] { NSBezierPath(ovalIn: NSRect(x: x, y: 414, width: 70, height: 30)).fill() }
    NSGraphicsContext.restoreGraphicsState()
    if mobile {
        let rgb = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<size {
            for x in 0..<size {
                let source = y * bitmap.bytesPerRow + x * 4, destination = y * rgb.bytesPerRow + x * 3
                for channel in 0..<3 { rgb.bitmapData![destination + channel] = bitmap.bitmapData![source + channel] }
            }
        }
        return rgb.representation(using: .png, properties: [:])!
    }
    return bitmap.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
if CommandLine.arguments.count > 2 {
    let mobile = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: mobile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try drawIcon(size: 1024, mobile: true).write(to: mobile)
}
if CommandLine.arguments.count > 3 {
    let brand = URL(fileURLWithPath: CommandLine.arguments[3])
    try FileManager.default.createDirectory(at: brand.deletingLastPathComponent(), withIntermediateDirectories: true)
    try drawIcon(size: 512).write(to: brand)
}
