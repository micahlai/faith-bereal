import SwiftUI
import UIKit

enum MannaWidgetTheme {
    static let primary = adaptiveColor(
        light: UIColor(red: 0.592, green: 0.353, blue: 0.141, alpha: 1),
        dark: UIColor(red: 0.659, green: 0.373, blue: 0.125, alpha: 1)
    )

    static let scripture = adaptiveColor(
        light: UIColor(red: 0.384, green: 0.337, blue: 0.647, alpha: 1),
        dark: UIColor(red: 0.686, green: 0.639, blue: 0.961, alpha: 1)
    )

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
