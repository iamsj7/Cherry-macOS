import AppKit
import SwiftUI

/// Colors that meet WCAG AA in light, dark, and Increase Contrast appearances.
/// Palette tests measure these against every background the app uses.
enum Palette {
    static let secondaryTextColor = adaptive(light: 0.34, dark: 0.72, lightHigh: 0.16, darkHigh: 0.90)
    static let successColor = adaptive(light: rgb(0x14, 0x6C, 0x2E), dark: rgb(0x5F, 0xD8, 0x7C),
                                       lightHigh: rgb(0x0B, 0x4F, 0x20), darkHigh: rgb(0x8B, 0xEB, 0xA2))
    static let destructiveColor = adaptive(light: rgb(0xB9, 0x1C, 0x1C), dark: rgb(0xFF, 0x7B, 0x72),
                                           lightHigh: rgb(0x8F, 0x12, 0x12), darkHigh: rgb(0xFF, 0xA8, 0xA1))
    /// Carries white text, so it stays dark in every appearance.
    static let destructiveFillColor = adaptive(light: rgb(0xB9, 0x1C, 0x1C), dark: rgb(0xD3, 0x2F, 0x2F),
                                               lightHigh: rgb(0x8F, 0x12, 0x12), darkHigh: rgb(0xD3, 0x2F, 0x2F))

    static let secondaryText = Color(nsColor: secondaryTextColor)
    static let success = Color(nsColor: successColor)
    static let destructive = Color(nsColor: destructiveColor)
    static let destructiveFill = Color(nsColor: destructiveFillColor)
    /// Opaque, so measured contrast holds on any desktop picture or Reduce Transparency setting.
    static let panelBackground = Color(nsColor: .windowBackgroundColor)

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    private static func adaptive(light: CGFloat, dark: CGFloat, lightHigh: CGFloat, darkHigh: CGFloat) -> NSColor {
        adaptive(light: NSColor(white: light, alpha: 1), dark: NSColor(white: dark, alpha: 1),
                 lightHigh: NSColor(white: lightHigh, alpha: 1), darkHigh: NSColor(white: darkHigh, alpha: 1))
    }

    private static func adaptive(light: NSColor, dark: NSColor, lightHigh: NSColor, darkHigh: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                               .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: lightHigh
            case .accessibilityHighContrastDarkAqua: darkHigh
            default: light
            }
        }
    }
}
