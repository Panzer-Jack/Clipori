import XCTest
@testable import CliporiCore

final class CategoryColorTests: XCTestCase {
    func testCustomHexColorsRoundTripAndNormalize() {
        for value in ["#000000", "#FFFFFF", "#17BFA9", "#FF006A"] {
            XCTAssertEqual(CategoryColor(storedValue: value).storedValue, value)
        }
        XCTAssertEqual(CategoryColor(storedValue: " #1ab3cf ").storedValue, "#1AB3CF")
        let cyan = CategoryColor(storedValue: "#00FFFF")
        XCTAssertEqual(cyan.red, 0); XCTAssertEqual(cyan.green, 1); XCTAssertEqual(cyan.blue, 1)
    }

    func testLegacyPaletteAndMalformedValuesRemainReadable() {
        XCTAssertEqual(CategoryColor(storedValue: "lavender"), CategoryColor(red: 0.65, green: 0.52, blue: 0.98))
        XCTAssertEqual(CategoryColor(storedValue: "blue"), CategoryColor(red: 0.42, green: 0.70, blue: 0.98))
        XCTAssertEqual(CategoryColor(storedValue: "peach"), CategoryColor(red: 1, green: 0.67, blue: 0.44))
        XCTAssertEqual(CategoryColor(storedValue: "mint"), CategoryColor(red: 0.39, green: 0.82, blue: 0.68))
        XCTAssertEqual(CategoryColor(storedValue: "pink"), CategoryColor(red: 0.94, green: 0.53, blue: 0.73))
        for invalid in ["", "#XYZ123", "#123", "#12345678", "#-12345", "#１２３４５６"] {
            XCTAssertEqual(CategoryColor(storedValue: invalid), CategoryColor(storedValue: "lavender"))
        }
    }
}
