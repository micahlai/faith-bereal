import SwiftUI
import UIKit

/// Save decisions use the same content-first cards as Timeline. Players remain
/// idle until Play, and photos only fetch their small preview while scrolling.
struct SavingBlessingPreview: View {
    @Environment(AppModel.self) private var model
    let blessing: Blessing
    var responses: [BlessingResponse] = []
    let memberName: String
    let circleName: String

    var body: some View {
        let resolved = model.resolvedBlessing(blessing)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(memberName).font(.headline).foregroundStyle(AppTheme.ink)
                Text(circleName).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                Text(blessing.submittedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }
            if let photo = resolved.photoURL {
                SavingPhotoPreview(photo: photo, preview: resolved.photoPreviewURL)
            }
            switch blessing.captureMode {
            case .typed: EmptyView()
            case .voice:
                Label("Voice blessing", systemImage: "waveform").font(.caption.weight(.semibold))
                if let audio = resolved.audioURL ?? blessing.audioURL {
                    AudioBlessingPlayer(url: audio).id(audio)
                } else {
                    unavailable("Audio unavailable", icon: "waveform.slash")
                }
            case .video:
                Label("Video blessing", systemImage: "video").font(.caption.weight(.semibold))
                if let video = resolved.videoURL ?? blessing.videoURL {
                    VideoBlessingPlayer(url: video).id(video)
                } else {
                    unavailable("Video unavailable", icon: "video.slash")
                }
            }
            if let body = blessing.body, !body.isEmpty {
                Text(body).font(.system(.subheadline, design: .serif))
                    .foregroundStyle(AppTheme.ink).lineLimit(15)
            }
            if let reference = blessing.scriptureReference {
                Label(reference.displayName, systemImage: "book.closed")
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.iris)
            }
            ForEach(responses.filter { $0.mode == .voice && !model.isAuthorBlocked($0.authorID) }) { response in
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Label("Voice response · \(responseAuthor(response))", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.semibold))
                    if let audio = model.resolvedResponse(response).audioURL ?? response.audioURL {
                        AudioBlessingPlayer(url: audio).id(audio)
                    } else {
                        unavailable("Response audio unavailable", icon: "waveform.slash")
                    }
                    Text(response.body).font(.system(.subheadline, design: .serif)).lineLimit(5)
                }
            }
        }
        .foregroundStyle(AppTheme.ink)
    }

    private func responseAuthor(_ response: BlessingResponse) -> String {
        if response.authorID == model.currentUser?.id { return "You" }
        return model.circles.first { $0.id == blessing.circleID }?.members
            .first { $0.id == response.authorID }?.displayName ?? "Member"
    }

    private func unavailable(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
    }
}

private struct SavingPhotoPreview: View {
    @Environment(AppModel.self) private var model
    let photo: URL
    let preview: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                AspectFitPhoto(image: image, maximumHeight: 160)
            } else {
                Label("Open photo", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .photoEnlargement(url: photo, title: "Blessing photo")
        .accessibilityIdentifier("saving.preview.photo")
        .task(id: "\(model.currentUser?.id.uuidString ?? "")|\(photo)|\(preview?.absoluteString ?? "")") {
            image = nil
            guard let account = model.currentUser?.id else { return }
            let loaded = await PhotoPreviewLoader.load(previewURL: preview, originalURL: photo, accountID: account)
            if !Task.isCancelled { image = loaded }
        }
    }
}
