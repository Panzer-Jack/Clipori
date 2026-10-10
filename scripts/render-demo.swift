import AppKit
import ImageIO
import UniformTypeIdentifiers

// An illustrated product walkthrough, drawn entirely offscreen from fictional data.
// Deliberately has no screen capture, pasteboard, database, Keychain, or network access.
// Run through make-demo.sh. Optional last argument renders a single time for inspection.
guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: render-demo output-directory brand.png [time-in-seconds]\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let brand = NSImage(contentsOfFile: CommandLine.arguments[2]) else { fatalError("Missing brand artwork") }
let width = 1200, height = 720, fps = 24, duration = 20.0
let white = NSColor(calibratedWhite: 0.97, alpha: 1)
func color(_ hex: Int, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, alpha: alpha)
}
let purple = color(0xBC9FFF), muted = color(0xA5A0B7), mint = color(0x7EDDBE)
func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
func ease(_ x: Double) -> Double { let v = clamp(x); return v * v * (3 - 2 * v) }
func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * clamp(p) }
func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double, _ fill: NSColor, stroke: NSColor? = nil, line: Double = 1) {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = line; path.stroke() }
}
func text(_ value: String, _ x: Double, _ y: Double, _ size: Double, _ ink: NSColor = white,
          weight: NSFont.Weight = .regular, width: Double = 900, mono: Bool = false, height: Double = 180) {
    let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = size * 0.30
    paragraph.lineBreakMode = .byTruncatingTail
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: height), withAttributes: [
        .font: font, .foregroundColor: ink, .paragraphStyle: paragraph
    ])
}
func line(_ points: [NSPoint], _ ink: NSColor, width: Double = 1) {
    guard let first = points.first else { return }
    let path = NSBezierPath(); path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    ink.setStroke(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
}
func dot(_ x: Double, _ y: Double, _ size: Double, _ ink: NSColor) {
    ink.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
}
func image(_ image: NSImage, _ x: Double, _ y: Double, _ size: Double, opacity: Double = 1) {
    image.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
}
func searchIcon(_ x: Double, _ y: Double) {
    muted.setStroke(); let path = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 10, height: 10)); path.lineWidth = 1.5; path.stroke()
    line([NSPoint(x: x + 8, y: y + 8), NSPoint(x: x + 13, y: y + 13)], muted, width: 1.5)
}
func cursor(_ p: NSPoint, clicking: Double = 0) {
    if clicking > 0 {
        let r = 12 + 15 * clicking
        let ring = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        purple.withAlphaComponent(1 - clicking).setStroke(); ring.lineWidth = 2; ring.stroke()
    }
    let path = NSBezierPath()
    for (i, point) in [(0.0, 0.0), (0, 24), (6, 18), (12, 31), (17, 28), (11, 16), (21, 16)].enumerated() {
        let value = NSPoint(x: p.x + point.0, y: p.y + point.1)
        if i == 0 { path.move(to: value) } else { path.line(to: value) }
    }
    path.close(); color(0x17121F).setFill(); path.fill(); white.setStroke(); path.lineWidth = 1.6; path.stroke()
}
struct Sample {
    let source: String, title: String, body: String, category: String, tint: NSColor
}
let samples = [
    Sample(source: "Notes", title: "A little spark", body: "Small ideas deserve\na place to stay.\n\nCopy now. Come back\nwhen inspiration calls.", category: "Inspiration", tint: color(0xEF9EBC)),
    Sample(source: "Notes", title: "Saturday, outside", body: "Sunset walk · 18:20\nRiverside path\n\nBring a camera.\nLeave room to wander.", category: "Life", tint: color(0xF5B27D)),
    Sample(source: "Xcode", title: "Spring, a little softer", body: "withAnimation(\n  .spring(\n    response: 0.30,\n    damping: 0.58\n  )\n) { show.toggle() }", category: "Code", tint: mint),
    Sample(source: "Safari", title: "A calmer interface", body: "developer.apple.com\n/design\n\nNatural feedback.\nThoughtful details.", category: "Learning", tint: color(0x7EBCF5)),
    Sample(source: "Screenshot", title: "Evening palette", body: "", category: "Inspiration", tint: purple)
]
let categories: [(String, Double, Double, NSColor)] = [
    ("All memories", 58, 117, purple), ("Work", 185, 67, purple),
    ("Learning", 264, 94, color(0x7EBCF5)), ("Life", 370, 59, color(0xF5B27D)),
    ("Code", 441, 67, mint), ("Inspiration", 520, 109, color(0xEF9EBC))
]

func drawCard(_ index: Int, x: Double, y: Double, h: Double, selected: Bool, hover: Double, moved: Bool) {
    let s = samples[index], tint = moved && [0, 2].contains(index) ? color(0xEF9EBC) : s.tint
    let y = y - hover * 6, w = 206.0
    box(x, y, w, h, 15, color(0xF2E9FF, 0.045), stroke: selected ? tint : color(0xFFFFFF, 0.14), line: selected ? 1.8 : 0.7)
    box(x + 14, y + 14, 27, 27, 8, tint.withAlphaComponent(0.18))
    if index == 2 { text("‹/›", x + 17, y + 18, 14, tint, weight: .bold) }
    else if index == 4 { text("▧", x + 20, y + 17, 16, tint) }
    else {
        for (j, length) in [13.0, 10.0, 13.0, 7.0].enumerated() {
            line([NSPoint(x: x + 21, y: y + 21 + Double(j) * 4), NSPoint(x: x + 21 + length, y: y + 21 + Double(j) * 4)], tint, width: 1.4)
        }
    }
    text(s.source, x + 49, y + 22, 10, tint, weight: .semibold, width: 110)
    text(String(format: "%02d", index + 1), x + 173, y + 22, 9, tint.withAlphaComponent(0.7), mono: true)
    text(s.title, x + 14, y + 56, 15, white, weight: .semibold, width: 180)
    if index == 4 {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + 82, width: 178, height: h - 121), xRadius: 9, yRadius: 9).addClip()
        NSGradient(starting: color(0x8673BD), ending: color(0xF5B299))!.draw(in: NSRect(x: x + 14, y: y + 82, width: 178, height: h - 121), angle: 90)
        dot(x + 120, y + 90, 38, color(0xFFE2BD))
        let mountain = NSBezierPath(); mountain.move(to: NSPoint(x: x + 14, y: y + h - 38))
        mountain.line(to: NSPoint(x: x + 65, y: y + 135)); mountain.line(to: NSPoint(x: x + 120, y: y + 171))
        mountain.line(to: NSPoint(x: x + 192, y: y + 125)); mountain.line(to: NSPoint(x: x + 192, y: y + h - 38)); mountain.close()
        color(0x4D446B).setFill(); mountain.fill(); NSGraphicsContext.restoreGraphicsState()
    } else {
        text(s.body, x + 14, y + 85, index == 2 ? 11 : 12, color(0xD4D0DF), width: 178, mono: index == 2, height: h - 127)
    }
    let category = moved && [0, 2].contains(index) ? "Inspiration" : s.category
    let tagWidth = Double(category.count) * 5.4 + 15
    box(x + 14, y + h - 30, tagWidth, 18, 8, tint.withAlphaComponent(0.13))
    text(category, x + 21, y + h - 28, 9, tint)
    text("10:24", x + 160, y + h - 27, 9, muted)
}

func draw(_ t: Double) {
    let context = NSGraphicsContext.current!.cgContext
    color(0x101019).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    // A designed, synthetic backdrop: never the user's wallpaper or a captured desktop.
    let glow = NSGradient(colors: [color(0x654482, 0.45), color(0x101019, 0)])!
    glow.draw(fromCenter: NSPoint(x: 1020, y: 520), radius: 0, toCenter: NSPoint(x: 1020, y: 520), radius: 650, options: .drawsAfterEndingLocation)
    let glow2 = NSGradient(colors: [color(0x283D59, 0.32), color(0x101019, 0)])!
    glow2.draw(fromCenter: NSPoint(x: 120, y: 520), radius: 0, toCenter: NSPoint(x: 120, y: 520), radius: 490, options: .drawsAfterEndingLocation)
    image(brand, 48, 25, 53)
    text("Clipori", 112, 33, 26, white, weight: .bold)
    text("Copy to remember. Search to rediscover.", 236, 44, 12, muted)
    box(982, 38, 162, 26, 13, color(0xFFFFFF, 0.045), stroke: color(0xFFFFFF, 0.12))
    dot(997, 48, 5, mint); text("NATIVE FOR macOS", 1010, 45, 10, color(0xC5BED7), weight: .medium)

    let stage = t < 4 ? 0 : t < 8 ? 1 : t < 13 ? 2 : 3
    let starts = [0.0, 4, 8, 13]
    let headings = ["Your memories. One shortcut.", "Click once. Keep just this.", "Gather a few. Drop them home.", "Remember it in your own words."]
    let captions = ["A floating shelf for the little things worth keeping.", "Each click replaces the clipboard with the selected card.", "Command-click to select. Drag the whole group to a category.", "Ask a question. Find the memory behind the answer."]
    let fade = ease((t - starts[stage]) / 0.3) * (1 - ease((t - 19.3) / 0.65))
    NSGraphicsContext.saveGraphicsState(); context.setAlpha(fade)
    text(String(format: "%02d", stage + 1) + " / " + ["A MOMENT AWAY", "ONE CLICK TO COPY", "ORGANIZE IN MOTION", "AI RECALL"][stage], 56, 113, 10, purple, weight: .bold)
    text(headings[stage], 52, 143, 36, white, weight: .semibold)
    text(captions[stage], 55, 199, 15, muted)
    if stage == 0 {
        box(1023, 188, 120, 36, 10, color(0xFFFFFF, 0.055), stroke: color(0xFFFFFF, 0.15))
        text("⇧ ⌘ V", 1044, 194, 19, purple, weight: .medium)
    }
    NSGraphicsContext.restoreGraphicsState()

    let revealTime = max(0, t - 0.45)
    let spring = 1 - exp(-revealTime * 8) * cos(revealTime * 12)
    let reveal = ease(revealTime / 0.25) * (1 - ease((t - 19.3) / 0.65))
    let answer = ease((t - 15.45) / 0.45)
    let sy = 268 + (1 - spring) * 100 - answer * 26
    let sh = 390 + answer * 26
    let moved = t >= 11.15
    NSGraphicsContext.saveGraphicsState(); context.setAlpha(reveal)
    // Match the product's translucent shelf, restrained borders, and category colors.
    let shadow = NSShadow(); shadow.shadowColor = color(0x000000, 0.45); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: 10)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    box(32, sy, 1136, sh, 25, color(0x24232F, 0.96)); NSGraphicsContext.restoreGraphicsState()
    let panel = NSBezierPath(roundedRect: NSRect(x: 32, y: sy, width: 1136, height: sh), xRadius: 25, yRadius: 25)
    NSGradient(starting: color(0xFFFFFF, 0.035), ending: color(0xB49CFF, 0.015))!.draw(in: panel, angle: 15)
    color(0xFFFFFF, 0.24).setStroke(); panel.lineWidth = 0.8; panel.stroke()
    image(brand, 52, sy + 17, 35, opacity: reveal)
    text("Clipori", 96, sy + 19, 17, white, weight: .bold)
    text("Keep every little spark", 96, sy + 41, 8, muted)
    box(640, sy + 20, 300, 32, 9, color(0xFFFFFF, 0.055), stroke: color(0xFFFFFF, 0.12), line: 0.6)
    searchIcon(652, sy + 29)
    let question = "When was the sunset walk?"
    let typed = stage == 3 ? String(question.prefix(Int(Double(question.count) * clamp((t - 13.4) / 1.3)))) : ""
    text(typed.isEmpty ? "Search memories, or ask AI…" : typed, 675, sy + 28, 11, typed.isEmpty ? muted : white, width: 249)
    if stage == 3 && t < 14.9 { text("│", 675 + Double(typed.count) * 5.85, sy + 26, 14, purple) }
    box(952, sy + 20, 91, 32, 9, purple.withAlphaComponent(t > 14.9 && t < 15.45 ? 0.30 : 0.15))
    text("✦  AI search", 963, sy + 29, 11, purple, weight: .semibold)
    box(1058, sy + 20, 34, 32, 9, color(0xFFFFFF, 0.045)); text("+", 1068, sy + 25, 20, white)
    box(1103, sy + 20, 34, 32, 9, color(0xFFFFFF, 0.045)); text("☷", 1113, sy + 27, 17, muted)

    for (index, c) in categories.enumerated() {
        let targeted = index == 5 && t > 10.35 && t < 11.3
        if index == 0 || targeted { box(c.1, sy + 70, c.2, 28, 8, targeted ? c.3.withAlphaComponent(0.22) : color(0xFFFFFF, 0.07), stroke: targeted ? c.3 : nil, line: 1.5) }
        dot(c.1 + 11, sy + 81, 5, c.3); text(c.0, c.1 + 23, sy + 78, 10, index == 0 || targeted ? white : muted, weight: index == 0 ? .semibold : .regular)
    }
    text(answer > 0 ? "AI search results" : "5 memories", 1027, sy + 79, 10, muted)
    if answer > 0 {
        NSGraphicsContext.saveGraphicsState(); context.setAlpha(answer * reveal)
        box(56, sy + 111, 1088, 61, 11, purple.withAlphaComponent(0.085), stroke: purple.withAlphaComponent(0.2), line: 0.6)
        text("✦", 71, sy + 127, 17, purple)
        text("Saturday at 18:20 — a sunset walk along the riverside path.", 102, sy + 124, 13, white, weight: .medium)
        text("From your note: “Saturday, outside”", 103, sy + 148, 10, purple)
        NSGraphicsContext.restoreGraphicsState()
    }
    let cy = sy + 123 + answer * 58, cardHeight = 220 - answer * 33
    NSGraphicsContext.saveGraphicsState(); panel.addClip()
    for index in 0..<5 {
        if answer > 0.95 && index != 1 { continue }
        let selected: Bool
        if stage == 1 { selected = index == (t < 6.2 ? 1 : 2) }
        else if stage == 2 { selected = t < 8.7 ? index == 0 : (index == 0 || index == 2) }
        else { selected = index == (stage == 3 ? 1 : 0) }
        let hovered = stage == 0 && index == 0 ? ease((t - 2) / 0.35) : 0
        let x = answer > 0.95 ? 56 : 56 + Double(index) * 220
        drawCard(index, x: x, y: cy, h: cardHeight, selected: selected, hover: hovered, moved: moved)
    }
    NSGraphicsContext.restoreGraphicsState()
    dot(57, sy + sh - 19, 4, mint)
    let status = stage == 1 ? "Copied · Clipboard replaced" : stage == 2 ? (moved ? "2 memories moved to Inspiration" : t < 8.7 ? "Command-click to select more" : "2 selected · Drag to a category") : "Demo space · Sample memories"
    text(status, 69, sy + sh - 24, 9, stage == 1 || moved && stage == 2 ? purple : muted)
    text("← →  Select     ↩  Paste     ⌘E  Edit     Esc  Hide", 873, sy + sh - 24, 9, muted)

    var p = NSPoint(x: 1160, y: 660), click = 0.0
    if stage == 0 {
        let f = ease((t - 1.65) / 0.65); p = NSPoint(x: mix(1130, 192, f), y: mix(670, cy + 99, f))
    } else if stage == 1 {
        let f = ease((t - 5.75) / 0.45); p = NSPoint(x: mix(362, 585, f), y: cy + 108)
        let elapsed = t - (t < 6.2 ? 4.25 : 6.25); click = elapsed > 0 && elapsed < 0.5 ? elapsed / 0.5 : 0
    } else if stage == 2 {
        let selecting = ease((t - 8.3) / 0.4), dragging = ease((t - 9.3) / 1.4)
        p = NSPoint(x: mix(mix(188, 590, selecting), 573, dragging), y: mix(cy + 106, sy + 83, dragging))
        if t < 9.25 { box(p.x + 28, p.y + 5, 36, 23, 6, color(0x15131E), stroke: color(0xFFFFFF, 0.2)); text("⌘", p.x + 36, p.y + 7, 15, purple) }
        if t >= 9.3 && t < 11.15 {
            box(p.x + 16, p.y + 33, 133, 62, 10, color(0x3B314E), stroke: purple.withAlphaComponent(0.55))
            box(p.x + 8, p.y + 26, 133, 62, 10, color(0x2C2639), stroke: purple)
            text("A little spark", p.x + 20, p.y + 38, 11, white, weight: .semibold)
            text("+ Spring, a little softer", p.x + 20, p.y + 58, 9, muted)
            dot(p.x + 125, p.y + 16, 22, purple); text("2", p.x + 132, p.y + 19, 12, color(0x20172F), weight: .bold)
        }
    } else {
        p = NSPoint(x: 998, y: sy + 38)
        let elapsed = t - 14.9; click = elapsed > 0 && elapsed < 0.5 ? elapsed / 0.5 : 0
        if answer > 0 { p = NSPoint(x: mix(998, 310, ease((t - 16.1) / 0.6)), y: mix(sy + 38, cy + 92, ease((t - 16.1) / 0.6))) }
    }
    if t > 1.65 { cursor(p, clicking: click) }
    NSGraphicsContext.restoreGraphicsState()

    text("ILLUSTRATED WALKTHROUGH  ·  SAMPLE DATA  ·  SCRIPTED AI", 35, 686, 9, muted)
    for i in 0..<4 {
        box(1016 + Double(i) * 34, 690, 26, 3, 1.5, i == stage ? purple : color(0xFFFFFF, 0.15))
    }
}

let singleTime = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) : nil
let frameCount = singleTime == nil ? Int(duration * Double(fps)) : 1
for frame in 0..<frameCount {
    try autoreleasepool {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        cg.translateBy(x: 0, y: Double(height)); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(singleTime ?? Double(frame) / Double(fps))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(String(format: "%04d.png", frame)))
    }
}
print("Rendered \(frameCount) synthetic frames (\(width)×\(height)).")
