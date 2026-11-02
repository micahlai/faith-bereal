import SwiftUI

struct TimelineRetentionBanner: View {
    @Environment(AppModel.self) private var model
    let onReview: () -> Void

    var body: some View {
        if model.showsExpiryReminder && !model.automaticallySavesLocally {
            Button(action: onReview) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Recordings are scheduled for 30-day removal", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                    Text(model.isReviewingExpiry ? "Checking your unsaved recordings…"
                         : model.expiryReviewError != nil ? "Check incomplete. Review and retry."
                         : model.expiryReviewCompletedAt == nil ? "Review recordings due for removal within 3 days"
                         : "\(model.expiringBlessings.count) blessings need saving within 3 days. Review recordings")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(12)
                .foregroundStyle(AppTheme.ink)
                .background(AppTheme.candle.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.pagePadding).padding(.bottom, 8)
            .accessibilityIdentifier("retention.banner")
        }
    }
}

struct RetentionReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var savingAll = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Review unsaved audio/video due within 3 days, including voice responses and older recordings still available during launch grace. Saves stay on this device, do not sync, and are lost if you uninstall. Removed recordings cannot be recovered.")
                    if model.isReviewingExpiry { ProgressView("Checking all your circles…") }
                    if let error = model.expiryReviewError { Text(error).foregroundStyle(AppTheme.missed) }
                    if let saveError { Text(saveError).foregroundStyle(AppTheme.missed) }
                    if model.expiryReviewCompletedAt == nil && !model.isReviewingExpiry && model.expiryReviewError == nil {
                        Text("Check your circles to find recordings approaching removal.")
                    }
                    Button("Check again") { Task { await model.reviewExpiringMedia() } }
                        .disabled(model.isReviewingExpiry || savingAll).frame(minHeight: 44)
                    if !model.expiringBlessings.isEmpty {
                        Button(savingAll ? "Saving…" : "Save all listed blessings") {
                            savingAll = true
                            Task {
                                saveError = nil
                                var failed = 0
                                for item in model.expiringBlessings {
                                    if !(await model.saveBlessing(item.blessing)) { failed += 1 }
                                }
                                if failed > 0 { saveError = "Some recordings could not be saved. Check your connection and device storage, then retry before removal." }
                                savingAll = false
                                await model.reviewExpiringMedia()
                            }
                        }.disabled(savingAll || model.isReviewingExpiry).frame(minHeight: 44)
                        .accessibilityIdentifier("retention.saveAll")
                    } else if model.expiryReviewCompletedAt != nil && !model.isReviewingExpiry && model.expiryReviewError == nil {
                        Text("No unsaved recordings are due within 3 days in your accessible circles.")
                    }
                }
                ForEach(model.expiringBlessings) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(item.memberName) · \(item.circleName)").font(.headline)
                        Text(item.blessing.body ?? "Recording").lineLimit(5)
                        Text(item.expiresAt <= .now ? "30-day limit reached. Save now while still available."
                             : "30-day limit: \(item.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        Button(model.savingBlessingIDs.contains(item.id) ? "Saving…" : "Save on this device") {
                            Task {
                                saveError = nil
                                if !(await model.saveBlessing(item.blessing)) {
                                    saveError = "This blessing could not be saved. Check your connection and device storage, then retry before removal."
                                }
                            }
                        }.disabled(savingAll || model.savingBlessingIDs.contains(item.id)).frame(minHeight: 44)
                        .accessibilityIdentifier("retention.save.\(item.id.uuidString)")
                    }.padding(.vertical, 4)
                }
                Section {
                    Button("Turn automatic saving on") { Task { await model.setAutomaticSavingEnabled(true) } }
                        .disabled(model.automaticallySavesLocally).frame(minHeight: 44)
                    Toggle("Show Timeline expiry reminder", isOn: Binding(get: { model.showsExpiryReminder }, set: { value in Task { await model.setExpiryReminderVisible(value) } }))
                    Text("You can change this reminder in User settings. Hiding it does not save recordings or change server removal.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Save before removal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.reviewExpiringMedia() }
        }
    }
}
