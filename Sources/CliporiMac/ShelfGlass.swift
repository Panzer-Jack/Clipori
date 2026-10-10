import AppKit
import SwiftUI

/// A single native backdrop blurs the desktop behind the entire shelf.
/// Cards share this surface instead of stacking independent blur layers.
struct ShelfGlass: NSViewRepresentable {
    var reduceTransparency: Bool

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
        view.alphaValue = reduceTransparency ? 1 : 0.82
    }
}
