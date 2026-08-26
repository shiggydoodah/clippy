import SwiftUI

nonisolated extension Color {
    /// Parses the same #RGB / #RRGGBB / #RRGGBBAA forms ItemClassifier
    /// accepts as a `colour` item, so the preview swatch never disagrees
    /// with classification.
    init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        var digits = String(trimmed.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        // Expand shorthand #RGB to #RRGGBB.
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt64(digits, radix: 16)
        else { return nil }

        let hasAlpha = digits.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        let red = Double((value >> (16 + shift)) & 0xFF) / 255
        let green = Double((value >> (8 + shift)) & 0xFF) / 255
        let blue = Double((value >> shift) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
