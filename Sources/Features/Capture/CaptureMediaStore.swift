import Foundation
import UIKit

enum CaptureMediaStore {
    private static let folderName = "BlessingCaptures"

    static func newRecordingURL(pathExtension: String) throws -> URL {
        let directory = try captureDirectory()
        return directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    static func persistVideo(from sourceURL: URL) throws -> URL {
        let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = try newRecordingURL(pathExtension: pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func persistPhoto(data: Data) throws -> URL {
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.88) else {
            throw BlessingError.cameraUnavailable
        }
        let destinationURL = try newRecordingURL(pathExtension: "jpg")
        try jpegData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private static func captureDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
