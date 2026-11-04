import AppKit
import XCTest
@testable import CherryTools

final class PaletteTests: XCTestCase {
    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua]

    private struct RGB {
        let red, green, blue, alpha: Double

        init(_ color: NSColor) {
            let color = color.usingColorSpace(.sRGB)!
            red = color.redComponent
            green = color.greenComponent
            blue = color.blueComponent
            alpha = color.alphaComponent
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            alpha = 1
        }

        func over(_ background: RGB) -> RGB {
            RGB(red: red * alpha + background.red * (1 - alpha), green: green * alpha + background.green * (1 - alpha),
                blue: blue * alpha + background.blue * (1 - alpha))
        }

        var luminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }
    }

    private func contrast(_ first: RGB, _ second: RGB) -> Double {
        let high = max(first.luminance, second.luminance), low = min(first.luminance, second.luminance)
        return (high + 0.05) / (low + 0.05)
    }

    private func forEachAppearance(_ body: (NSAppearance.Name, [(String, RGB)]) -> Void) {
        for name in appearances {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let window = RGB(NSColor.windowBackgroundColor)
                let backgrounds: [(String, RGB)] = [
                    ("window", window),
                    ("control", RGB(NSColor.controlBackgroundColor).over(window)),
                    ("text", RGB(NSColor.textBackgroundColor).over(window)),
                    ("grouped row", RGB(NSColor.quaternarySystemFill).over(window)),
                    ("hover", RGB(NSColor.labelColor.withAlphaComponent(0.06)).over(window)),
                    ("selected row", RGB(NSColor.controlAccentColor.withAlphaComponent(0.16)).over(window))
                ]
                body(name, backgrounds)
            }
        }
    }

    func testTextMeetsAAOnEveryBackground() {
        forEachAppearance { name, backgrounds in
            for (label, color) in [("secondary", Palette.secondaryTextColor), ("success", Palette.successColor),
                                   ("destructive", Palette.destructiveColor), ("primary", NSColor.labelColor)] {
                for (background, value) in backgrounds {
                    let ratio = contrast(RGB(color).over(value), value)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(label) on \(background) in \(name.rawValue)")
                }
            }
        }
    }

    func testButtonTextOnDestructiveFillMeetsAA() {
        forEachAppearance { name, _ in
            let ratio = contrast(RGB(NSColor.white), RGB(Palette.destructiveFillColor))
            XCTAssertGreaterThanOrEqual(ratio, 4.5, name.rawValue)
        }
    }

    func testDestructiveFillStandsOutFromThePanel() {
        forEachAppearance { name, backgrounds in
            let ratio = contrast(RGB(Palette.destructiveFillColor), backgrounds[0].1)
            XCTAssertGreaterThanOrEqual(ratio, 3, name.rawValue)
        }
    }

    func testSelectionBarMeetsNonTextContrast() {
        forEachAppearance { name, backgrounds in
            let selected = backgrounds[backgrounds.count - 1].1
            let ratio = contrast(RGB(NSColor.labelColor).over(selected), selected)
            XCTAssertGreaterThanOrEqual(ratio, 3, name.rawValue)
        }
    }
}
