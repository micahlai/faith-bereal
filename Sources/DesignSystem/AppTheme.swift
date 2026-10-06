import SwiftUI

enum AppTheme {
    static let canvas = Color("Canvas", bundle: nil)
    static let surface = Color("Surface", bundle: nil)
    static let ink = Color("Ink", bundle: nil)
    static let secondaryInk = Color("SecondaryInk", bundle: nil)
    static let primary = Color("Manna", bundle: nil)
    static let iris = Color("Iris", bundle: nil)
    static let dawn = Color("Dawn", bundle: nil)
    static let candle = Color("Candle", bundle: nil)
    static let missed = Color("Missed", bundle: nil)
    static let divider = Color("Divider", bundle: nil)

    static let pagePadding: CGFloat = 20
    static let controlHeight: CGFloat = 52
    static let cardRadius: CGFloat = 22
}

extension View {
    func blessingCard() -> some View {
        self
            .padding(20)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.divider.opacity(0.65), lineWidth: 1)
            }
    }
}
