import SwiftUI

struct TimelineRetentionBanner: View {
    @Environment(AppModel.self) private var model
    let onReview: () -> Void

    var body: some View {
        if model.shouldShowTimelineExpiryReminder {
            Button(action: onReview) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Recordings are scheduled for 30-day removal", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        model.isReviewingExpiry
                            ? "Checking your unsaved recordings…"
                            : model.expiryReviewError != nil
                                ? "Check incomplete. Review and retry."
                                : model.expiryReviewCompletedAt == nil
                                    ? "Review recordings due for removal within 3 days"
                                    : "\(model.expiringBlessings.count) blessings need saving within 3 days. Review recordings"
                    )
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
            ZStack {
                AppTheme.canvas.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        introduction
                        ForEach(model.expiringBlessings) { item in
                            VStack(alignment: .leading, spacing: 16) {
                                SavingBlessingPreview(
                                    blessing: item.blessing, responses: item.responses,
                                    memberName: item.memberName, circleName: item.circleName)
                                Label(
                                    item.expiresAt <= .now
                                        ? "30-day limit reached. Save now while still available."
                                        : "30-day limit: \(item.expiresAt.formatted(date: .abbreviated, time: .shortened))",
                                    systemImage: "clock.badge.exclamationmark"
                                )
                                .font(.caption.weight(.medium)).foregroundStyle(AppTheme.candle)
                                Button(model.savingBlessingIDs.contains(item.id) ? "Saving…" : "Save on this device") {
                                    Task {
                                        saveError = nil
                                        if !(await model.saveBlessing(item.blessing)) {
                                            saveError =
                                                "This blessing could not be saved. Check your connection and device storage, then retry before removal."
                                        } else {
                                            await model.reviewExpiringMedia()
                                        }
                                    }
                                }
                                .buttonStyle(MannaPrimaryButtonStyle())
                                .disabled(savingAll || model.savingBlessingIDs.contains(item.id))
                                .accessibilityIdentifier("retention.save.\(item.id.uuidString)")
                            }.blessingCard()
                        }
                        preferences
                    }
                    .frame(maxWidth: 680).padding(AppTheme.pagePadding).frame(maxWidth: .infinity)
                }.accessibilityIdentifier("saving.review.scroll")
            }
            .safeAreaInset(edge: .bottom) {
                if !model.expiringBlessings.isEmpty {
                    saveAllControl
                        .padding(.horizontal, AppTheme.pagePadding).padding(.vertical, 12)
                        .frame(maxWidth: .infinity).background(AppTheme.canvas)
                }
            }
            .navigationTitle("Save before removal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
            .task { await model.reviewExpiringMedia() }
        }
    }

    private var saveAllControl: some View {
        Button {
            savingAll = true
            Task {
                saveError = nil
                var failed = 0
                for item in model.expiringBlessings {
                    if !(await model.saveBlessing(item.blessing)) { failed += 1 }
                }
                if failed > 0 {
                    saveError =
                        "Some recordings could not be saved. Check your connection and device storage, then retry before removal."
                }
                savingAll = false
                await model.reviewExpiringMedia()
            }
        } label: {
            Text(savingAll ? "Saving…" : "Save all")
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: AppTheme.controlHeight)
        }
        .buttonStyle(MannaPrimaryButtonStyle())
        .disabled(savingAll || model.isReviewingExpiry)
        .accessibilityIdentifier("retention.saveAll")
        .accessibilityLabel(savingAll ? "Saving…" : "Save all listed blessings")
        .accessibilityValue("\(model.expiringBlessings.count) listed blessings")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Save your recordings", systemImage: "bookmark")
                .font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
            Text(
                "Preview recordings due within 3 days, then save a private copy on this device."
            )
            if model.isReviewingExpiry { ProgressView("Checking all your circles…") }
            if let error = model.expiryReviewError { Text(error).foregroundStyle(AppTheme.missed) }
            if let saveError { Text(saveError).foregroundStyle(AppTheme.missed) }
            if model.expiryReviewCompletedAt == nil && !model.isReviewingExpiry && model.expiryReviewError == nil {
                Text("Check your circles to find recordings approaching removal.")
            }
            Button("Check again") { Task { await model.reviewExpiringMedia() } }.buttonStyle(.bordered)
                .disabled(model.isReviewingExpiry || savingAll).frame(minHeight: 44)
            if model.expiringBlessings.isEmpty && model.expiryReviewCompletedAt != nil && !model.isReviewingExpiry
                && model.expiryReviewError == nil
            {
                Text("No unsaved recordings are due within 3 days in your accessible circles.")
            }
        }.blessingCard()
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {

            Button("Turn automatic saving on") { Task { await model.setAutomaticSavingEnabled(true) } }.buttonStyle(
                .bordered
            )
            .disabled(model.automaticallySavesLocally || savingAll || model.isChangingAutomaticSaving).frame(
                minHeight: 44)
            Toggle(
                "Show Timeline expiry reminder",
                isOn: Binding(
                    get: { model.showsExpiryReminder },
                    set: { value in Task { await model.setExpiryReminderVisible(value) } }))
            Text(
                "The list includes voice responses and older recordings still available during launch grace. Copies do not sync and are lost if you uninstall. Removed recordings cannot be recovered. Change the reminder in User settings; hiding it does not save recordings or change removal."
            )
            .font(.footnote)
        }.blessingCard()
    }
}
