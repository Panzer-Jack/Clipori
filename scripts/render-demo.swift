import AppKit
import ImageIO
import UniformTypeIdentifiers

// An illustrated product walkthrough, drawn entirely offscreen from fictional data.
// Deliberately has no screen capture, pasteboard, database, Keychain, or network access.
// Run through make-demo.sh. Optional last argument renders a single time for inspection.
guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: render-demo output-directory brand.png [time-in-seconds] [en|zh]\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let brand = NSImage(contentsOfFile: CommandLine.arguments[2]) else { fatalError("Missing brand artwork") }
let chinese = CommandLine.arguments.dropFirst(3).contains("zh")
let translations: [String: String] = [
    "Copy to remember. Search to rediscover.": "复制即备忘，想起时就来找回。",
    "NATIVE FOR macOS": "为 macOS 原生打造",
    "ILLUSTRATED WALKTHROUGH  ·  SAMPLE DATA  ·  SCRIPTED AI": "产品示意动画 · 虚构数据 · 预设 AI 回复",
    "01 / A MOMENT AWAY": "01 / 随时唤起", "02 / ONE CLICK TO COPY": "02 / 单击复制",
    "03 / ORGANIZE IN MOTION": "03 / 多选归类", "04 / AI RECALL": "04 / AI 找回",
    "Your memories. One shortcut.": "一个快捷键，记忆就在手边。",
    "Click once. Keep just this.": "轻轻一点，复制这一条。",
    "Gather a few. Drop them home.": "选中几条，拖进同一个分类。",
    "Remember it in your own words.": "记得大概，就可以问问 AI。",
    "A floating shelf for the little things worth keeping.": "用底部卡片栏，留住值得记下的小事。",
    "Each click replaces the clipboard with the selected card.": "单击卡片，用选中内容替换剪贴板。",
    "Command-click to select. Drag the whole group to a category.": "按住 Command 多选，再将整组拖入分类。",
    "Ask a question. Find the memory behind the answer.": "用自己的话提问，找回有原文依据的记忆。",
    "Keep every little spark": "留住每一闪灵感",
    "Search memories, or ask AI…": "搜索备忘，或问问 AI…",
    "When was the sunset walk?": "看日落的散步约在什么时候？",
    "✦  AI search": "✦  AI 找回", "AI search results": "AI 找回结果", "5 memories": "5 条备忘",
    "Saturday at 18:20 — a sunset walk along the riverside path.": "周六 18:20，沿河边小路散步看日落。",
    "From your note: “Saturday, outside”": "来自备忘：「周六，去走走」",
    "Click a card to copy": "单击卡片即可复制", "Copied · Clipboard replaced": "已复制 · 剪贴板已替换",
    "2 memories moved to Inspiration": "已将 2 条备忘移入灵感", "Command-click to select more": "按住 Command 点击多选",
    "2 selected · Drag to a category": "已选 2 条 · 拖入分类", "Demo space · Sample memories": "演示空间 · 虚构备忘",
    "← →  Select     ↩  Paste     ⌘E  Edit     Esc  Hide": "← → 选择    ↩ 粘贴    ⌘E 编辑    Esc 收起",
    "Notes": "备忘录", "Screenshot": "截图", "All memories": "全部记忆", "Work": "工作",
    "Learning": "学习", "Life": "生活", "Code": "代码", "Inspiration": "灵感",
    "A little spark": "一点小灵感", "Saturday, outside": "周六，去走走",
    "Spring, a little softer": "再柔和一点的回弹", "+ Spring, a little softer": "+ 再柔和一点的回弹",
    "A calmer interface": "更安静的界面", "Evening palette": "傍晚的色彩",
    "Small ideas deserve\na place to stay.\n\nCopy now. Come back\nwhen inspiration calls.": "小小的念头，\n也值得有个地方安放。\n\n先复制下来，\n等灵感来时再找回。",
    "Sunset walk · 18:20\nRiverside path\n\nBring a camera.\nLeave room to wander.": "日落散步 · 18:20\n沿着河边小路\n\n记得带上相机，\n给闲逛留一点时间。",
    "developer.apple.com\n/design\n\nNatural feedback.\nThoughtful details.": "developer.apple.com\n/design\n\n自然的反馈，\n细致的设计。"
]
func localized(_ value: String) -> String { chinese ? translations[value] ?? value : value }

let width = 1200, height = 720, fps = 50, duration = 20.0
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
    (localized(value) as NSString).draw(in: NSRect(x: x, y: y, width: width, height: height), withAttributes: [
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
    let w = 206.0, highlight = clamp(hover)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: x + w / 2, y: y + h / 2 - hover * 6)
    context.scaleBy(x: 1 + hover * 0.018, y: 1 + hover * 0.018)
    context.translateBy(x: -x - w / 2, y: -y - h / 2)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.06 + highlight * 0.05)
    shadow.shadowBlurRadius = 6 + highlight * 4
    shadow.shadowOffset = NSSize(width: 0, height: 3 + highlight * 2)
    shadow.set()
    box(x, y, w, h, 15, color(0xF2E9FF, 0.045 + highlight * 0.025), stroke: selected ? tint : color(0xFFFFFF, 0.14 + highlight * 0.14), line: selected ? 1.8 : 0.7)
    NSGraphicsContext.restoreGraphicsState()
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

// Drawing and hit testing share the same layout and continuous pointer trajectory.
struct WalkthroughState {
    let t: Double
    var stage: Int { t < 4 ? 0 : t < 8 ? 1 : t < 13 ? 2 : 3 }
    var answer: Double { ease((t - 15.45) / 0.45) }
    var shelfY: Double {
        let elapsed = max(0, t - 0.45)
        return 268 + exp(-elapsed * 8) * cos(elapsed * 12) * 100 - answer * 26
    }
    var cardY: Double { shelfY + 123 + answer * 58 }
    var cardHeight: Double { 220 - answer * 33 }
    var dragging: Bool { t >= 9.3 && t < 11.15 }
    var pointerVisible: Bool { t >= 1.4 }
    var pointer: NSPoint {
        let keys: [(Double, NSPoint)] = [
            (1.4, NSPoint(x: 1150, y: 660)), (2.1, NSPoint(x: 188, y: cardY + 108)),
            (2.7, NSPoint(x: 188, y: cardY + 108)), (3.6, NSPoint(x: 362, y: cardY + 108)),
            (5.75, NSPoint(x: 362, y: cardY + 108)), (6.2, NSPoint(x: 585, y: cardY + 108)),
            (7.3, NSPoint(x: 585, y: cardY + 108)), (7.9, NSPoint(x: 188, y: cardY + 108)),
            (8.3, NSPoint(x: 188, y: cardY + 108)), (8.7, NSPoint(x: 590, y: cardY + 108)),
            (9.3, NSPoint(x: 590, y: cardY + 108)), (10.7, NSPoint(x: 573, y: shelfY + 83)),
            (11.5, NSPoint(x: 573, y: shelfY + 83)), (12.05, NSPoint(x: 585, y: cardY + 108)),
            (12.5, NSPoint(x: 585, y: cardY + 108)), (13.2, NSPoint(x: 790, y: shelfY + 38)),
            (14.45, NSPoint(x: 790, y: shelfY + 38)), (14.85, NSPoint(x: 998, y: shelfY + 38)),
            (15.8, NSPoint(x: 998, y: shelfY + 38)), (16.5, NSPoint(x: 165, y: cardY + 92)),
            (18.1, NSPoint(x: 165, y: cardY + 92)), (18.9, NSPoint(x: 1140, y: 655)),
            (duration, NSPoint(x: 1140, y: 655))
        ]
        for pair in zip(keys, keys.dropFirst()) where t <= pair.1.0 {
            let p = ease((t - pair.0.0) / (pair.1.0 - pair.0.0))
            return NSPoint(x: mix(pair.0.1.x, pair.1.1.x, p), y: mix(pair.0.1.y, pair.1.1.y, p))
        }
        return keys.last!.1
    }
    func cardRect(_ index: Int) -> NSRect? {
        if answer > 0.95 && index != 1 { return nil }
        return NSRect(x: answer > 0.95 ? 56 : 56 + Double(index) * 220, y: cardY, width: 206, height: cardHeight)
    }
    func isSelected(_ index: Int) -> Bool {
        if t < 4.25 { return index == 0 }
        if t < 6.25 { return index == 1 }
        if t < 8.1 { return index == 2 }
        if t < 8.75 { return index == 0 }
        if t < 13 { return index == 0 || index == 2 }
        return index == 1
    }
}
let hoverStep = 1.0 / 240
let hoverFrames: [[Double]] = {
    var positions = Array(repeating: 0.0, count: 5), velocities = positions, frames = [positions]
    for step in 1...Int(duration / hoverStep) {
        let scene = WalkthroughState(t: Double(step) * hoverStep)
        let pointer = scene.pointer
        for index in 0..<5 {
            // Match MemoryCard's stationary hit region and enter/leave spring parameters.
            let inside = scene.pointerVisible && !scene.dragging && (scene.cardRect(index)?.contains(pointer) == true)
            let target = inside ? 1.0 : 0
            let omega = 2 * Double.pi / (inside ? 0.28 : 0.24)
            let damping = inside ? 0.64 : 0.86
            let acceleration = omega * omega * (target - positions[index]) - 2 * damping * omega * velocities[index]
            velocities[index] += acceleration * hoverStep
            positions[index] += velocities[index] * hoverStep
        }
        frames.append(positions)
    }
    return frames
}()

func drawFooter(active: Int) {
    text("ILLUSTRATED WALKTHROUGH  ·  SAMPLE DATA  ·  SCRIPTED AI", 35, 686, 9, muted)
    for i in 0..<4 {
        box(1016 + Double(i) * 34, 690, 26, 3, 1.5, i == active ? purple : color(0xFFFFFF, 0.15))
    }
}

func draw(_ t: Double) {
    let scene = WalkthroughState(t: t), pointer = scene.pointer
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

    let stage = scene.stage
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
    let reveal = ease(revealTime / 0.25) * (1 - ease((t - 19.3) / 0.65))
    let answer = scene.answer
    let sy = scene.shelfY
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
    let question = localized("When was the sunset walk?")
    let typed = stage == 3 ? String(question.prefix(Int(Double(question.count) * clamp((t - 13.4) / 1.3)))) : ""
    text(typed.isEmpty ? "Search memories, or ask AI…" : typed, 675, sy + 28, 11, typed.isEmpty ? muted : white, width: 249)
    if stage == 3 && t < 14.9 { text("│", 675 + (typed as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width, sy + 26, 14, purple) }
    box(952, sy + 20, 91, 32, 9, purple.withAlphaComponent(t > 14.9 && t < 15.45 ? 0.30 : 0.15))
    text("✦  AI search", 963, sy + 29, 11, purple, weight: .semibold)
    box(1058, sy + 20, 34, 32, 9, color(0xFFFFFF, 0.045)); text("+", 1068, sy + 25, 20, white)
    box(1103, sy + 20, 34, 32, 9, color(0xFFFFFF, 0.045)); text("☷", 1113, sy + 27, 17, muted)

    for (index, c) in categories.enumerated() {
        let targeted = index == 5 && scene.dragging && NSRect(x: c.1, y: sy + 70, width: c.2, height: 28).contains(pointer)
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
    let hoverFrame = min(hoverFrames.count - 1, max(0, Int(t / hoverStep)))
    NSGraphicsContext.saveGraphicsState(); panel.addClip()
    for index in 0..<5 {
        guard let rect = scene.cardRect(index) else { continue }
        drawCard(index, x: rect.minX, y: rect.minY, h: rect.height, selected: scene.isSelected(index), hover: hoverFrames[hoverFrame][index], moved: moved)
    }
    NSGraphicsContext.restoreGraphicsState()
    dot(57, sy + sh - 19, 4, mint)
    let status = stage == 1 ? (t < 4.25 ? "Click a card to copy" : "Copied · Clipboard replaced") : stage == 2 ? (moved ? "2 memories moved to Inspiration" : t < 8.75 ? "Command-click to select more" : "2 selected · Drag to a category") : "Demo space · Sample memories"
    text(status, 69, sy + sh - 24, 9, stage == 1 || moved && stage == 2 ? purple : muted)
    text("← →  Select     ↩  Paste     ⌘E  Edit     Esc  Hide", 873, sy + sh - 24, 9, muted)

    let p = pointer
    var click = 0.0
    for clickTime in [4.25, 6.25, 8.1, 8.75, 14.9] {
        let elapsed = t - clickTime
        if elapsed > 0 && elapsed < 0.5 { click = elapsed / 0.5 }
    }
    if stage == 2 {
        if t < 9.25 { box(p.x + 28, p.y + 5, 36, 23, 6, color(0x15131E), stroke: color(0xFFFFFF, 0.2)); text("⌘", p.x + 36, p.y + 7, 15, purple) }
        if scene.dragging {
            box(p.x + 16, p.y + 33, 133, 62, 10, color(0x3B314E), stroke: purple.withAlphaComponent(0.55))
            box(p.x + 8, p.y + 26, 133, 62, 10, color(0x2C2639), stroke: purple)
            text("A little spark", p.x + 20, p.y + 38, 11, white, weight: .semibold)
            text("+ Spring, a little softer", p.x + 20, p.y + 58, 9, muted)
            dot(p.x + 125, p.y + 16, 22, purple); text("2", p.x + 132, p.y + 19, 12, color(0x20172F), weight: .bold)
        }
    }
    if scene.pointerVisible { cursor(p, clicking: click) }
    NSGraphicsContext.restoreGraphicsState()

    drawFooter(active: stage)
}

let singleTime = CommandLine.arguments.dropFirst(3).compactMap(Double.init).first
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
