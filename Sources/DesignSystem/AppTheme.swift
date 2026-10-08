import SwiftUI

enum AppTheme {
    static let canvas = Color("Canvas", bundle: nil)
    static let surface = Color("Surface", bundle: nil)
    static let ink = Color("Ink", bundle: nil)
    static let secondaryInk = Color("SecondaryInk", bundle: nil)
    // Text/tint and white-on-orange actions require different dark-mode values.
    static let primary = Color("MannaInk", bundle: nil)
    static let actionFill = Color("Manna", bundle: nil)
    static let iris = Color("Iris", bundle: nil)
    static let dawn = Color("Dawn", bundle: nil)
    static let candle = Color("Candle", bundle: nil)
    static let missed = Color("Missed", bundle: nil)
    static let divider = Color("Divider", bundle: nil)

    static let pagePadding: CGFloat = 20
    static let controlHeight: CGFloat = 52
    static let cardRadius: CGFloat = 22
}

struct MannaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(AppTheme.actionFill, in: Capsule())
            .overlay {
                if configuration.isPressed {
                    Capsule().fill(.black.opacity(0.1)).allowsHitTesting(false)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension View {
    func blessingCard() -> some View {
        modifier(BlessingCardModifier())
    }
}

private struct BlessingCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.divider.opacity(contrast == .increased ? 1 : 0.65), lineWidth: contrast == .increased ? 2 : 1)
            }
    }
}
