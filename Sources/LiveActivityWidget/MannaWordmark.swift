import SwiftUI

struct MannaWordmark: View {
    let width: CGFloat

    var body: some View {
        Image("MannaWordmark")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityHidden(true)
    }
}
