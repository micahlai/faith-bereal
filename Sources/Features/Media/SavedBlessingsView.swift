import SwiftUI

/// Reads only the account's completed on-device archives. No server reads or mutations.
struct SavedBlessingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Private copies saved on this device. These open without internet; new posts and responses still need a connection.")
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                ForEach(model.savedArchiveRecords, id: \.blessing.id) { record in
                    NavigationLink {
                        SavedBlessingReader(blessingID: record.blessing.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.blessing.submittedAt, style: .date).font(.headline)
                            Text(record.blessing.body ?? "Saved recording").lineLimit(3)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("savedArchive.\(record.blessing.id)")
                }
            }
            .navigationTitle("Saved on this device")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct SavedBlessingReader: View {
    @Environment(AppModel.self) private var model
    let blessingID: UUID

    var body: some View {
        Group {
            if let record = model.savedBlessings[blessingID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(record.blessing.submittedAt, style: .date)
                            .font(.headline)
                        Text(record.blessing.body ?? "Saved recording").textSelection(.enabled)
                        if let reference = record.blessing.scriptureReference {
                            Label(reference.displayName, systemImage: "book.closed")
                            Text("The Bible reference is saved. Reading the passage may need a connection.")
                                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        }
                        if let photo = record.blessing.photoURL, photo.isFileURL {
                            BlessingPhotoView(url: photo)
                            SaveBlessingMediaButton(url: photo, kind: .photo)
                        }
                        if let audio = record.blessing.audioURL, audio.isFileURL {
                            AudioBlessingPlayer(url: audio).id(audio)
                        }
                        if record.blessing.captureMode == .voice, record.blessing.audioURL == nil {
                            Label("Saved audio is missing from this device", systemImage: "waveform.slash")
                        }
                        if record.blessing.captureMode == .video, record.blessing.videoURL == nil {
                            Label("Saved video is missing from this device", systemImage: "video.slash")
                        }
                        if let video = record.blessing.videoURL, video.isFileURL {
                            VideoBlessingPlayer(url: video).id(video)
                            SaveBlessingMediaButton(url: video, kind: .video)
                        }
                        if !record.responses.isEmpty {
                            Text("Saved responses").font(.headline)
                            ForEach(record.responses) { response in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(response.body).textSelection(.enabled)
                                    if let audio = response.audioURL, audio.isFileURL {
                                        AudioBlessingPlayer(url: audio).id(audio)
                                    } else if response.mode == .voice {
                                        Label("Saved audio is missing from this device", systemImage: "waveform.slash")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.pagePadding)
                }
                .background(AppTheme.canvas)
            } else {
                ContentUnavailableView("Saved copy unavailable", systemImage: "bookmark.slash")
            }
        }
        .navigationTitle("Saved blessing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
