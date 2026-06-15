import AppKit
import UsageCore

enum AppColors {
    /// Color for a window's percentage: threshold level wins (orange/red), else the
    /// user's custom color, else the system label color (adapts to light/dark).
    static func color(level: UsageLevel, customHex: String) -> NSColor {
        switch level {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal: return NSColor(hex: customHex) ?? .labelColor
        }
    }
}

extension NSColor {
    /// Parses "#RRGGBB" / "RRGGBB". Returns nil for empty/invalid input.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X",
                      Int(round(rgb.redComponent * 255)),
                      Int(round(rgb.greenComponent * 255)),
                      Int(round(rgb.blueComponent * 255)))
    }
}
