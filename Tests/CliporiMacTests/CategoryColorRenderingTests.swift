import XCTest
import AppKit
import SwiftUI
@testable import CliporiMac

final class CategoryColorRenderingTests: XCTestCase {
    func testStoredCustomColorsSurviveUIConversion() {
        for hex in ["#000000", "#FFFFFF", "#17BFA9", "#FF006A"] {
            XCTAssertEqual(Color.category(hex).categoryStoredValue, hex)
        }
    }

    func testPickerConvertsGrayscaleAndDisplayP3ToSRGB() throws {
        XCTAssertEqual(Color(nsColor: NSColor(white: 0.5, alpha: 1)).categoryStoredValue, "#808080")
        let source = NSColor(displayP3Red: 0.2, green: 0.7, blue: 0.5, alpha: 1)
        let converted = try XCTUnwrap(source.usingColorSpace(.sRGB))
        let stored = try XCTUnwrap(Color(nsColor: source).categoryStoredValue)
        let restored = try XCTUnwrap(NSColor(Color.category(stored)).usingColorSpace(.sRGB))
        XCTAssertEqual(restored.redComponent, max(0, min(1, converted.redComponent)), accuracy: 1 / 255)
        XCTAssertEqual(restored.greenComponent, max(0, min(1, converted.greenComponent)), accuracy: 1 / 255)
        XCTAssertEqual(restored.blueComponent, max(0, min(1, converted.blueComponent)), accuracy: 1 / 255)
    }
}
