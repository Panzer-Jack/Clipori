import Foundation

/// Category colors are stored as opaque sRGB hex values. Older named colors remain valid.
public struct CategoryColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        self.red = channel(red); self.green = channel(green); self.blue = channel(blue)
    }

    public init(storedValue: String) {
        let value = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#"), value.utf8.count == 7,
           value.dropFirst().utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
           let rgb = UInt32(value.dropFirst(), radix: 16) {
            self.init(red: Double((rgb >> 16) & 255) / 255,
                      green: Double((rgb >> 8) & 255) / 255,
                      blue: Double(rgb & 255) / 255)
            return
        }
        switch value {
        case "blue": self.init(red: 0.42, green: 0.70, blue: 0.98)
        case "peach": self.init(red: 1, green: 0.67, blue: 0.44)
        case "mint": self.init(red: 0.39, green: 0.82, blue: 0.68)
        case "pink": self.init(red: 0.94, green: 0.53, blue: 0.73)
        default: self.init(red: 0.65, green: 0.52, blue: 0.98)
        }
    }

    public var storedValue: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()),
               Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
