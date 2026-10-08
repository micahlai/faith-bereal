import SwiftUI

struct AutomaticSavingSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showingKeepChoices = false

    var body: some View {
        Toggle("Automatically save locally", isOn: Binding(
            get: { model.automaticallySavesLocally },
            set: { enabled in
                if enabled { Task { await model.setAutomaticSavingEnabled(true) } }
                else { showingKeepChoices = true }
            }
        ))
        .accessibilityIdentifier("saving.automaticToggle")
        .disabled(model.isChangingAutomaticSaving || model.isChoosingAutomaticSaving)
        .sheet(isPresented: $showingKeepChoices) { AutomaticSaveKeepView() }
        Text("Keep private copies of visible blessings from all your circles while manna is open. Audio/video expire on the server after 30 days. Copies use this device’s storage, don’t sync, and are lost if you uninstall the app.")
            .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
        if let error = model.automaticSavingError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(AppTheme.missed)
        }
        if !model.automaticallySavesLocally, !model.automaticSavedBlessings.isEmpty {
            Button("Manage remaining automatic copies") { showingKeepChoices = true }
                .frame(minHeight: 44)
        }
    }
}

private struct AutomaticSaveKeepView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choice: AutomaticSaveKeepChoice = .all
    @State private var selectedIDs: Set<UUID> = []
    @State private var ready = false
    @State private var showingPermanentRemoval = false

    private var records: [SavedBlessingRecord] { model.automaticSavedBlessings }
    private var keptIDs: Set<UUID> {
        guard let userID = model.currentUser?.id else { return [] }
        return choice.keptIDs(records: records, userID: userID, selectedIDs: selectedIDs)
    }
    private var removesExpiredMedia: Bool {
        records.contains { !keptIDs.contains($0.blessing.id) && $0.containsExpiredMedia }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose what stays on this device after automatic saving is off. Kept copies become normal manual saves; your existing manual saves are never removed.")
                    Picker("Keep saved copies", selection: $choice) {
                        ForEach(AutomaticSaveKeepChoice.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }.pickerStyle(.inline)
                }
                if choice == .selected {
                    Section("Pick blessings to keep") {
                        if records.isEmpty { Text("No automatic copies yet.").foregroundStyle(.secondary) }
                        ForEach(records, id: \.blessing.id) { record in
                            selectionRow(record)
                        }
                    }
                }
                Section {
                    Text("\(keptIDs.count) kept · \(records.count - keptIDs.count) removed")
                    if removesExpiredMedia {
                        Label("Some removed audio/video have expired. Removing those device copies is permanent.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.missed)
                    }
                    Text("Text and Bible references stay in circle history. Available server media can be downloaded again, but expired media cannot be recovered after its device copy is removed.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .navigationTitle("Saved copies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(!ready || model.isChangingAutomaticSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Turn off") {
                        if removesExpiredMedia { showingPermanentRemoval = true }
                        else { apply() }
                    }.disabled(!ready || model.isChangingAutomaticSaving)
                }
            }
            .overlay { if !ready || model.isChangingAutomaticSaving { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
            .alert("Permanently remove expired media?", isPresented: $showingPermanentRemoval) {
                Button("Remove copies and turn off", role: .destructive) { apply() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Some audio/video are past their 30-day server expiry. These device copies may be the only remaining copies. Kept blessings and existing manual saves are unaffected.")
            }
        }
        .interactiveDismissDisabled(!ready || model.isChangingAutomaticSaving)
        .task {
            await model.pauseAutomaticSavingForSelection()
            selectedIDs = Set(records.map(\.blessing.id))
            ready = true
        }
        .onDisappear { model.resumeAutomaticSavingAfterSelection() }
    }

    private func selectionRow(_ record: SavedBlessingRecord) -> some View {
        Toggle(isOn: Binding(
            get: { selectedIDs.contains(record.blessing.id) },
            set: { keep in
                if keep { selectedIDs.insert(record.blessing.id) }
                else { selectedIDs.remove(record.blessing.id) }
            }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text(authorAndCircle(for: record.blessing)).font(.subheadline.weight(.medium))
                Text(record.blessing.body ?? "").lineLimit(3)
                Text(record.blessing.submittedAt, format: .dateTime.month().day().year())
                    .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }.padding(.vertical, 4)
        }
    }

    private func apply() {
        let keep = keptIDs
        Task { if await model.disableAutomaticSaving(keepingIDs: keep) { dismiss() } }
    }

    private func authorAndCircle(for blessing: Blessing) -> String {
        let circle = model.circles.first { $0.id == blessing.circleID }
        let name = blessing.authorID == model.currentUser?.id ? "You"
            : circle?.members.first { $0.id == blessing.authorID }?.displayName ?? "Member"
        return "\(name) · \(circle?.name ?? "Circle")"
    }
}
