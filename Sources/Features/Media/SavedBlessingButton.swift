import SwiftUI

struct SavedBlessingButton: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing
    @State private var showingExplanation = false
    @State private var showingPermanentRemoval = false

    private var isSaved: Bool { model.savedBlessings[blessing.id] != nil }

    var body: some View {
        Button {
            if let saved = model.savedBlessings[blessing.id] {
                if saved.containsExpiredMedia { showingPermanentRemoval = true }
                else { Task { await model.unsaveBlessing(blessing) } }
            } else if let userID = model.currentUser?.id,
                      !UserDefaults.standard.bool(forKey: "saving.explained.\(userID.uuidString)") {
                showingExplanation = true
            } else {
                Task { _ = await model.saveBlessing(blessing) }
            }
        } label: {
            HStack(spacing: 8) {
                if model.savingBlessingIDs.contains(blessing.id) {
                    ProgressView().controlSize(.small)
                    Text("Saving blessing…")
                } else {
                    Label(isSaved ? "Unsave blessing" : "Save blessing", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(model.savingBlessingIDs.contains(blessing.id))
        .alert("Save this blessing on your device?", isPresented: $showingExplanation) {
            Button("Save blessing") {
                if let userID = model.currentUser?.id {
                    UserDefaults.standard.set(true, forKey: "saving.explained.\(userID.uuidString)")
                }
                Task { _ = await model.saveBlessing(blessing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Audio and video leave the server after 14 days. Saving keeps this blessing, its photo/audio/video, Bible reference, and current responses on this device so you can open them from Timeline later.\n\nOnly you can use this copy. Future responses aren't added automatically. It doesn't sync to other devices and will be lost if you uninstall manna. Saving to Photos is a separate option.")
        }
        .alert("Permanently remove saved media?", isPresented: $showingPermanentRemoval) {
            Button("Unsave permanently", role: .destructive) {
                Task { await model.unsaveBlessing(blessing) }
            }
            Button("Keep saved", role: .cancel) {}
        } message: {
            Text("Some audio or video in this saved blessing is past its 14-day expiry and is no longer available from the server. Unsaving deletes your device's copy permanently. The text and Bible reference remain in history.")
        }
    }
}

struct SavedBlessingStatusView: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                if model.savedBlessings[blessing.id] != nil {
                    Label("Saved", systemImage: "bookmark.fill")
                        .foregroundStyle(AppTheme.primary)
                } else if let warning = model.mediaExpiryWarning(for: blessing, at: context.date) {
                    Label(warning, systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(AppTheme.candle)
                }
            }
            .font(.caption.weight(.medium))
        }
    }
}
