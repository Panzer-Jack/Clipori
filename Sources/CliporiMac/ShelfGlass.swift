import AppKit
import SwiftUI

/// Keep the shelf and card surfaces together; only the backdrop changes opacity.
struct ShelfBackground: View {
    var opacity: Double
    var reduceTransparency: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if !reduceTransparency && opacity < 1 { ShelfGlass() }
            Rectangle().fill(scheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
                .opacity(reduceTransparency ? 1 : opacity)
            if !reduceTransparency {
                LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.09 : 0.24), .clear, Color.clipori.opacity(0.018)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

struct ShelfCardBackground: View {
    var tint: Color
    var selected: Bool
    var hover: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(scheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.24))
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [.white.opacity(hover ? 0.12 : 0.075), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 16).fill(tint.opacity(selected ? 0.045 : 0.018))
        }
    }
}

/// A single native backdrop blurs the desktop behind the entire shelf.
/// Cards share this surface instead of stacking independent blur layers.
private struct ShelfGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 24
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = 0.82
    }
}
