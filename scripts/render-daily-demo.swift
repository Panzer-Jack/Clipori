import AppKit

// Fictional, offscreen walkthrough. No clipboard, screen capture, database, or network access.
// Usage: render-daily-demo OUTPUT_DIRECTORY zh|en [SECONDS]
guard CommandLine.arguments.count >= 3, ["zh", "en"].contains(CommandLine.arguments[2]) else {
    fputs("Usage: render-daily-demo OUTPUT_DIRECTORY zh|en [SECONDS]\n", stderr); exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let chinese = CommandLine.arguments[2] == "zh"
let width = 1200, height = 800, fps = 10, duration = 30
func l(_ zh: String, _ en: String) -> String { chinese ? zh : en }
func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255, alpha: 1)
}
let white = color(0xF4F1FA), muted = color(0xA8A3B8), purple = color(0xC0A4FA)
let border = color(0x413B4D), surface = color(0x25222C), green = color(0x91D6B8)
func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ fill: NSColor, radius: Double = 8, stroke: NSColor? = nil) {
    let p = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius)
    fill.setFill(); p.fill()
    if let stroke { stroke.setStroke(); p.lineWidth = 1; p.stroke() }
}
func text(_ s: String, _ x: Double, _ y: Double, _ size: Double = 15, _ ink: NSColor = white, w: Double = 900, bold: Bool = false) {
    let p = NSMutableParagraphStyle(); p.lineSpacing = 5
    (s as NSString).draw(in: NSRect(x: x, y: y, width: w, height: 100), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: ink, .paragraphStyle: p
    ])
}
func rule(_ x: Double, _ y: Double, _ w: Double, _ h: Double = 1) { box(x, y, w, h, border, radius: 0) }
func symbol(_ name: String, _ x: Double, _ y: Double, _ size: Double = 16, _ ink: NSColor = purple) {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return }
    let tinted = NSImage(size: img.size, flipped: false) { rect in
        img.draw(in: rect); ink.setFill(); rect.fill(using: .sourceIn); return true
    }
    tinted.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
func button(_ title: String, _ x: Double, _ y: Double, _ w: Double, active: Bool = false) {
    box(x, y, w, 34, active ? color(0x40334F) : color(0x302C38), stroke: active ? purple : border)
    text(title, x + 12, y + 7, 13, active ? purple : white, w: w - 20)
}
func check(_ x: Double, _ y: Double, _ done: Bool) {
    box(x, y, 17, 17, done ? purple : surface, radius: 4, stroke: done ? purple : muted)
    if done { symbol("checkmark", x + 3, y + 3, 11, surface) }
}
func task(_ title: String, _ y: Double, _ done: Bool = false) {
    check(602, y + 2, done); text(title, 631, y, 15, done ? muted : white, w: 476)
    if done {
        let font = NSFont.systemFont(ofSize: 15)
        let length = min(470, (title as NSString).size(withAttributes: [.font: font]).width)
        box(631, y + 10, length, 1, muted, radius: 0)
    }
}
func pointer(_ x: Double, _ y: Double, _ t: Double) {
    let pulse = (t * 2).truncatingRemainder(dividingBy: 1)
    let ring = NSBezierPath(ovalIn: NSRect(x: x - 12 - pulse * 8, y: y - 12 - pulse * 8, width: 24 + pulse * 16, height: 24 + pulse * 16))
    purple.withAlphaComponent(0.6 * (1 - pulse)).setStroke(); ring.lineWidth = 2; ring.stroke()
    symbol("cursorarrow", x - 2, y - 2, 25, white)
}
func typed(_ s: String, _ progress: Double) -> String { String(s.prefix(Int(Double(s.count) * min(1, max(0, progress))))) }

let steps = [l("手动写下今天的安排", "Start with your own plan"), l("让 AI 整理当天剪贴板", "Draft from today's clipboard"),
             l("审阅后加入，Pin 持续跟进", "Review, add, and pin"), l("次日继续，进度也保留", "Carry work into the next day"),
             l("全部完成，下一天不再延续", "Finish it; leave it off tomorrow"), l("随时回看往期备忘录", "Revisit any previous day")]
let captions = [l("直接编辑事项、备注和子任务，不配置 AI 也能使用。", "Edit items, notes, and subtasks directly. AI setup is optional."),
                l("先核对原文、修改建议，再选择加入；AI 不会自动改写手写内容。", "Check the source and edit the draft before adding it. Your writing stays intact."),
                l("点亮事项旁的 Pin，让尚未完成的事情每天保留。", "Pin an item to carry it forward while there is still work to do."),
                l("日期推进至 10.15：保留已完成进度，再勾掉剩下的子任务。", "Advance to Oct 15: keep earlier progress, then check off the remaining work."),
                l("日期推进至 10.16：已完成事项留在原日期，不再带入新的一天。", "Advance to Oct 16: completed work stays on its original page."),
                l("选择 10.14，仍能看到那一天的安排与完成状态。", "Choose Oct 14 to see the plan and progress as they were that day.")]

func draw(_ t: Double) {
    let stage = min(5, Int(t / 5))
    let historical = stage == 5, tomorrow = stage == 3, empty = stage == 4
    let day = empty ? "10.16" : tomorrow ? "10.15" : "10.14"
    let pinned = stage >= 3 || (stage == 2 && t >= 12.5)
    let allDone = stage == 3 && t >= 17.8
    box(0, 0, 1200, 800, color(0x16131D), radius: 0)
    text("CLIPORI  /  " + l("每日备忘录", "DAILY NOTES"), 42, 23, 12, purple, bold: true)
    text(steps[stage], 42, 53, 31, white, bold: true)
    text(String(format: "%02d / 06", stage + 1), 1060, 61, 16, muted)
    for index in 0..<6 { box(42 + Double(index) * 188, 108, 172, 3, index == stage ? purple : border, radius: 1) }

    box(40, 135, 1120, 540, surface, radius: 14, stroke: border)
    box(41, 136, 206, 538, color(0x211E27), radius: 14)
    for (i, tint) in [0xF37876, 0xEDC367, 0x86C997].enumerated() { box(57 + Double(i) * 20, 151, 11, 11, color(tint), radius: 6) }
    text(l("每日备忘录", "Daily notes"), 60, 190, 19, white, w: 180, bold: true)
    button(l("☀ 回到今天", "☀ Back to today"), 55, 233, 176, active: true)
    text(l("往期备忘录", "Previous notes"), 60, 291, 12, muted, w: 170)
    let maxDay = stage >= 4 ? 16 : stage == 3 ? 15 : 14
    for (i, d) in (12...maxDay).reversed().enumerated() {
        let y = 321.0 + Double(i) * 43
        let selected = d == (empty ? 16 : tomorrow ? 15 : 14)
        if selected { box(53, y - 4, 181, 35, color(0x3A3049)) }
        symbol("doc.text", 65, y + 4, 14, selected ? purple : muted)
        text("2026-10-\(d)", 91, y + 2, 14, selected ? white : muted, w: 130)
    }
    text(l("每日一页，接着推进。", "One day at a time."), 60, 637, 11, muted, w: 180)
    rule(247, 136, 1, 538)
    text(l("\(day) 备忘录", "\(day) Notes"), 276, 178, 29, white, w: 470, bold: true)
    text(historical ? l("往期备忘录 · 修改仅影响本页", "Previous notes · Edits affect this page only") : l("记录今天要推进的事情", "What would you like to move forward today?"), 278, 221, 12, muted, w: 510)
    button(l("✦ AI 整理", "✦ AI draft"), 880, 180, 112, active: true)
    button(l("＋ 添加事项", "+ Add item"), 1004, 180, 128)
    symbol("pin.fill", 278, 258, 14)
    text(l("每天保留，全部完成后停止延续", "Carry forward until all tasks are complete"), 301, 256, 12, muted, w: 600)
    rule(248, 289, 911)

    if empty {
        symbol("checklist", 675, 380, 42)
        text(l("给今天留一份清单", "Make room for today"), 580, 441, 22, white, w: 420, bold: true)
        button(l("＋ 添加第一件事", "+ Add your first item"), 593, 493, 220)
    } else {
        box(276, 314, 855, 270, surface, radius: 0, stroke: border)
        box(277, 315, 853, 42, color(0x2E2936), radius: 0)
        text(l("事项", "Item"), 294, 325, 14, white, bold: true)
        text(l("子任务", "Subtasks"), 602, 325, 14, white, bold: true)
        rule(583, 314, 1, 270); rule(276, 357, 855)
        let title = l("发布准备", "Release preparation")
        text(stage == 0 ? typed(title, t / 1.1) : title, 294, 382, 17, white, w: 238, bold: true)
        symbol(pinned ? "pin.fill" : "pin", 547, 384, 17, pinned ? purple : muted)
        text(l("周五前完成", "Ready by Friday"), 294, 416, 13, muted, w: 260)
        if pinned { text(allDone ? l("已完成 · 明日不再延续", "Done · Won't carry forward") : l("每天保留", "Keep for the next day"), 294, 460, 11, allDone ? muted : purple, w: 270) }
        if stage >= 2 { text(l("▸ 剪贴板来源（1）", "▸ Clipboard source (1)"), 294, 494, 11, muted, w: 265) }
        let first = l("整理发布清单", "Prepare the release checklist")
        task(stage == 0 ? typed(first, (t - 1.1) / 1.5) : first, 382, t >= 3.2)
        if stage >= 2 {
            task(l("完成回归测试", "Run regression tests"), 425, stage == 3 && t >= 16.7)
            task(l("更新发布说明", "Update the release notes"), 468, allDone)
        }
        text(l("＋ 添加子任务", "+ Add subtask"), 602, stage >= 2 ? 519 : 431, 12, muted, w: 300)
        text(l("＋ 添加事项", "+ Add item"), 292, 607, 13, muted)
    }
    rule(248, 632, 911)
    text(l("✓ 已保存到本机", "✓ Saved locally"), 277, 647, 11, muted)
    if stage == 0 && t > 3 && t < 3.8 { pointer(609, 390, t) }
    if stage == 2 && t >= 12 && t < 13.6 { pointer(553, 391, t) }
    if stage == 3 && t >= 16 && t < 18.5 { pointer(610, t < 17.5 ? 435 : 478, t) }
    if stage == 5 && t < 26 { pointer(149, 414, t) }

    if stage == 1 {
        box(248, 136, 911, 538, NSColor.black.withAlphaComponent(0.44), radius: 0)
        box(351, 151, 702, 466, color(0x2C2734), radius: 14, stroke: border)
        text(l("✦ AI 辅助整理", "✦ AI-assisted draft"), 377, 173, 22, white, bold: true)
        text("2026-10-14", 379, 207, 12, muted)
        text(l("基于当天剪贴板与已有事项，先审阅再加入。", "Review suggestions based on this day's clipboard and existing items."), 379, 238, 13, white, w: 640)
        text(l("发送至你配置的 AI 服务 · 示例回复为预设内容", "Uses your configured AI service · Scripted reply in this demo"), 379, 263, 12, muted, w: 640)
        box(376, 302, 652, 226, color(0x362D43), stroke: border)
        check(395, 324, true)
        text(l("补充到：发布准备", "Add to: Release preparation"), 424, 320, 16, white, w: 570, bold: true)
        text("□  " + l("完成回归测试", "Run regression tests"), 424, 355, 14)
        let edit = l("更新发布说明", "Update the release notes")
        text("□  " + (t >= 7 ? edit : l("准备说明", "Prepare notes")), 424, 386, 14)
        if t >= 7 && t < 8 { box(chinese ? 542 : 607, 386, 1, 19, purple, radius: 0) }
        text(l("▾ 剪贴板来源（1）", "▾ Clipboard source (1)"), 424, 425, 12, purple)
        text(l("团队讨论 · 原文", "Team chat · Original excerpt"), 424, 450, 11, muted)
        text(l("“发布前完成回归测试，并更新发布说明。”", "“Before release, run regression tests and update the release notes.”"), 424, 475, 13, white, w: 574)
        button(l("重新整理", "Try again"), 377, 558, 115)
        button(l("取消", "Cancel"), 765, 558, 90)
        button(l("加入所选（1）", "Add selected (1)"), 868, 558, 160, active: true)
        if t >= 9 { pointer(953, 572, t) }
    }
    text(captions[stage], 42, 703, 17, white, w: 1118)
    text(l("产品示意动画 · 虚构数据 · 预设 AI 回复 · 时间经过已压缩", "ILLUSTRATED WALKTHROUGH · FICTIONAL DATA · SCRIPTED AI · TIME COMPRESSED"), 42, 764, 10, muted)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let moment = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) : nil
for frame in 0..<(moment == nil ? duration * fps : 1) {
    try autoreleasepool {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        cg.translateBy(x: 0, y: Double(height)); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(moment ?? Double(frame) / Double(fps))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(String(format: "%04d.png", frame)))
    }
}
print("Rendered \(chinese ? "Chinese" : "English") daily notes walkthrough.")
