import SwiftUI
import UIKit

struct SaveBlessingMediaButton: View {
    let url: URL
    let kind: BlessingSavedMediaKind
    @State private var isSaving = false
    @State private var message: String?
    @State private var permissionDenied = false

    var body: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
                Text(isSaving ? "Saving…" : kind == .photo ? "Save photo" : "Save video")
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(isSaving)
        .alert(permissionDenied ? "Photos access needed" : "Save to Photos", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            if permissionDenied {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
            }
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        permissionDenied = false
        defer { isSaving = false }
        do {
            try await BlessingMediaSaver().save(url: url, kind: kind)
            message = kind == .photo ? "Photo saved to your Photos library." : "Video saved to your Photos library."
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, !AppModel.isCancellation(error) else { return }
            permissionDenied = (error as? BlessingMediaSaveError) == .permissionDenied
            message = error.localizedDescription
        }
    }
}
