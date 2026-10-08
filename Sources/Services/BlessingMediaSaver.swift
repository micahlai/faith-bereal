import Foundation
@preconcurrency import Photos
import UniformTypeIdentifiers

enum BlessingSavedMediaKind: Sendable {
    case photo
    case video
}

struct BlessingDownloadedMedia: Sendable {
    let url: URL
    let isTemporary: Bool
}

protocol BlessingMediaDownloading: Sendable {
    func localFile(for url: URL, kind: BlessingSavedMediaKind) async throws -> BlessingDownloadedMedia
}

protocol BlessingMediaPhotoLibrary: Sendable {
    func requestAddAccess() async -> Bool
    func save(fileURL: URL, kind: BlessingSavedMediaKind) async throws
}

struct BlessingMediaSaver: Sendable {
    var downloader: any BlessingMediaDownloading = URLSessionBlessingMediaDownloader()
    var library: any BlessingMediaPhotoLibrary = SystemBlessingPhotoLibrary()

    func save(url: URL, kind: BlessingSavedMediaKind) async throws {
        guard await library.requestAddAccess() else { throw BlessingMediaSaveError.permissionDenied }
        try Task.checkCancellation()
        let file = try await downloader.localFile(for: url, kind: kind)
        defer {
            if file.isTemporary { try? FileManager.default.removeItem(at: file.url) }
        }
        try Task.checkCancellation()
        try await library.save(fileURL: file.url, kind: kind)
    }
}

struct SystemBlessingPhotoLibrary: BlessingMediaPhotoLibrary {
    func requestAddAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    func save(fileURL: URL, kind: BlessingSavedMediaKind) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: kind == .photo ? .photo : .video, fileURL: fileURL, options: nil)
        }
    }
}

struct URLSessionBlessingMediaDownloader: BlessingMediaDownloading {
    func localFile(for url: URL, kind: BlessingSavedMediaKind) async throws -> BlessingDownloadedMedia {
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BlessingMediaSaveError.unavailable
            }
            return BlessingDownloadedMedia(url: url, isTemporary: false)
        }
        guard url.scheme == "https" else { throw BlessingMediaSaveError.unavailable }
        let (download, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let mimeType = response.mimeType,
              let type = UTType(mimeType: mimeType),
              type.conforms(to: kind == .photo ? .image : .movie),
              let pathExtension = type.preferredFilenameExtension else {
            throw BlessingMediaSaveError.unavailable
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-blessing-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try FileManager.default.moveItem(at: download, to: destination)
        return BlessingDownloadedMedia(url: destination, isTemporary: true)
    }
}

enum BlessingMediaSaveError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Allow manna circle to add photos in Settings, then try saving again."
        case .unavailable:
            "This photo or video is unavailable. Refresh the blessing and try again."
        }
    }
}
