import UIKit
import XCTest

@testable import BlessingCircle

@MainActor
final class AccessibilityContrastTests: XCTestCase {
    func testSemanticTextMeetsContrastInBothAppearancesAndIncreasedContrast() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { mutableTraits in
                    mutableTraits.userInterfaceStyle = style
                    mutableTraits.accessibilityContrast = contrast
                }
                for background in ["Canvas", "Surface"] {
                    for foreground in ["Ink", "SecondaryInk", "MannaInk", "Iris", "Dawn", "Candle", "Missed"] {
                        let ratio = try contrastRatio(foreground, background, traits: traits)
                        XCTAssertGreaterThanOrEqual(
                            ratio, 4.5, "\(foreground)/\(background), \(style), \(contrast): \(ratio)")
                    }
                }
                let action = try luminance("Manna", traits: traits)
                XCTAssertGreaterThanOrEqual(1.05 / (action + 0.05), 4.5, "White action text")
                XCTAssertGreaterThanOrEqual(
                    try contrastRatio("Surface", "Iris", traits: traits), 4.5, "Selected verse text")
                if contrast == .high {
                    XCTAssertGreaterThanOrEqual(
                        try contrastRatio("Divider", "Canvas", traits: traits), 3,
                        "Increased-contrast boundaries")
                }
            }
        }
    }

    private func contrastRatio(_ foreground: String, _ background: String, traits: UITraitCollection)
        throws -> Double
    {
        let first = try luminance(foreground, traits: traits)
        let second = try luminance(background, traits: traits)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func luminance(_ name: String, traits: UITraitCollection) throws -> Double {
        let color = try XCTUnwrap(UIColor(named: name)).resolvedColor(with: traits)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
