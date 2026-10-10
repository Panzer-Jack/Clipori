import SwiftUI
import CliporiCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    static let clipori = Color(red: 0.65, green: 0.52, blue: 0.98)
    static func category(_ name: String) -> Color {
        let value = CategoryColor(storedValue: name)
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue)
    }

    var categoryStoredValue: String? {
        #if os(macOS)
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return CategoryColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent).storedValue
        #else
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = UIColor(self).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3 else { return nil }
        return CategoryColor(red: components[0], green: components[1], blue: components[2]).storedValue
        #endif
    }
}

struct CategoryColorPicker: View {
    @Binding var selection: String
    var compact = false

    var body: some View {
        let color = Binding<Color>(get: { Color.category(selection) }, set: { value in
            if let storedValue = value.categoryStoredValue { selection = storedValue }
        })
        Group {
            if compact {
                ColorPicker(L("分类颜色"), selection: color, supportsOpacity: false).labelsHidden()
            } else {
                ColorPicker(L("分类颜色"), selection: color, supportsOpacity: false)
            }
        }.fixedSize().help(L("分类颜色")).accessibilityLabel(L("分类颜色"))
    }
}

struct MascotView: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: size * 0.16, y: size * 0.4))
                path.addLine(to: CGPoint(x: size * 0.12, y: size * 0.06))
                path.addLine(to: CGPoint(x: size * 0.39, y: size * 0.24))
                path.addQuadCurve(to: CGPoint(x: size * 0.64, y: size * 0.24), control: CGPoint(x: size * 0.5, y: size * 0.19))
                path.addLine(to: CGPoint(x: size * 0.89, y: size * 0.04))
                path.addLine(to: CGPoint(x: size * 0.85, y: size * 0.42))
                path.addQuadCurve(to: CGPoint(x: size * 0.51, y: size * 0.91), control: CGPoint(x: size * 1.1, y: size * 0.88))
                path.addQuadCurve(to: CGPoint(x: size * 0.16, y: size * 0.4), control: CGPoint(x: size * -0.12, y: size * 0.9))
            }.fill(LinearGradient(colors: [Color(red: 0.87, green: 0.79, blue: 1), .clipori], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: size * 0.17) {
                Capsule().frame(width: size * 0.055, height: size * 0.13)
                Capsule().frame(width: size * 0.055, height: size * 0.13)
            }.foregroundStyle(Color(red: 0.21, green: 0.16, blue: 0.32)).offset(y: size * 0.06)
            Text("ᴗ").font(.system(size: size * 0.25, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.3, green: 0.2, blue: 0.4)).offset(y: size * 0.18)
            HStack(spacing: size * 0.44) {
                Ellipse().fill(Color.pink.opacity(0.6)).frame(width: size * 0.13, height: size * 0.065)
                Ellipse().fill(Color.pink.opacity(0.6)).frame(width: size * 0.13, height: size * 0.065)
            }.offset(y: size * 0.17)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QuietButton: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Color.clipori.opacity(0.19) : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct KeyHint: View {
    let key: String
    var body: some View {
        Text(key).font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}
