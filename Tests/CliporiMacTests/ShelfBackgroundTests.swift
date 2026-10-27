import XCTest
import AppKit
import SwiftUI
@testable import CliporiMac

final class ShelfBackgroundTests: XCTestCase {
    @MainActor
    func testOpaqueAndReducedTransparencyBackgroundsHideWindowsInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            for (opacity, reduceTransparency) in [(1.0, false), (0.0, true), (0.85, true)] {
                let red = try sample(opacity: opacity, reduceTransparency: reduceTransparency, scheme: scheme, behind: .red)
                let blue = try sample(opacity: opacity, reduceTransparency: reduceTransparency, scheme: scheme, behind: .blue)
                XCTAssertEqual(red.redComponent, blue.redComponent, accuracy: 0.01)
                XCTAssertEqual(red.greenComponent, blue.greenComponent, accuracy: 0.01)
                XCTAssertEqual(red.blueComponent, blue.blueComponent, accuracy: 0.01)
                XCTAssertEqual(red.alphaComponent, 1, accuracy: 0.01)
                if scheme == .light { XCTAssertGreaterThan(red.redComponent, 0.9) }
                else { XCTAssertLessThan(red.redComponent, 0.3) }
            }
        }
    }

    @MainActor
    private func sample(opacity: Double, reduceTransparency: Bool, scheme: ColorScheme, behind: Color) throws -> NSColor {
        let view = ShelfBackground(opacity: opacity, reduceTransparency: reduceTransparency)
            .frame(width: 100, height: 100)
            .background(behind)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        // Render these shapes into a CPU bitmap. ImageRenderer.cgImage initializes
        // Metal, which can abort on the virtual GPU of hosted Intel runners.
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        var rendered = false
        renderer.render { size, draw in
            XCTAssertEqual(size, CGSize(width: 100, height: 100))
            draw(context)
            rendered = true
        }
        XCTAssertTrue(rendered, "The background must render before sampling its pixels")
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return try XCTUnwrap(bitmap.colorAt(x: 50, y: 50)?.usingColorSpace(.sRGB))
    }
}
