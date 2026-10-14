import SwiftUI

struct DiagnosticCollectionSettings: View {
    @Environment(AppModel.self) private var model
    @State private var isChanging = false

    var body: some View {
        let collection = model.diagnosticCollection
        Section {
            Toggle("Share diagnostic data", isOn: Binding(get: { collection.isEnabled }, set: { enabled in
                isChanging = true
                Task { await collection.setEnabled(enabled); isChanging = false }
            }))
            .frame(minHeight: 44)
            .disabled(isChanging || model.currentUser == nil)
            .accessibilityIdentifier("diagnostics.consent")
            if collection.isEnabled {
                LabeledContent("Queued records", value: "\(collection.queuedCount)")
                if let sentAt = collection.lastUploadedAt {
                    LabeledContent("Last sent", value: sentAt.formatted(date: .abbreviated, time: .shortened))
                }
                Button {
                    Task { await collection.sendNow(); await collection.refreshSummary() }
                } label: {
                    HStack {
                        Text(collection.isSending ? "Sending diagnostics…" : "Send diagnostics now")
                        Spacer()
                        if collection.isSending { ProgressView() }
                    }.frame(minHeight: 44)
                }
                .disabled(collection.isSending || !collection.uploadsRemotely)
                .accessibilityIdentifier("diagnostics.sendNow")
                if !collection.uploadsRemotely {
                    Text("Local demo keeps these records on this device.").foregroundStyle(.secondary)
                }
            }
            if let status = collection.status {
                Text(status).foregroundStyle(.secondary).accessibilityIdentifier("diagnostics.status")
            }
        } header: { Text("Field testing") } footer: {
            Text("Optional. Share timings, transfer sizes, failure categories, app build, and a random session code with manna’s developer. Reports are linked to your signed-in account and retained for 14 days, with scheduled cleanup. Blessing text, recordings, photos, names, links, and credentials are excluded. Records send in small batches while manna is open. Turning this off discards unsent records; an upload already underway may finish.")
        }
        .task {
            await collection.refreshSummary()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                await collection.refreshSummary()
            }
        }
    }
}
