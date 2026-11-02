import SwiftUI

struct SavedBlessingStatusView: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                if let saved = model.savedBlessings[blessing.id], saved.coversPostMedia(blessing) {
                    Label(saved.containsRecording(for: blessing) ? "Saved on this device" : "Text saved · recording unavailable", systemImage: "bookmark.fill")
                        .foregroundStyle(AppTheme.primary)
                }
                if let warning = model.mediaExpiryWarning(for: blessing, at: context.date) {
                    Label(warning, systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(AppTheme.candle)
                }
            }
            .font(.caption.weight(.medium))
        }
    }
}
