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

    static func persistProfilePhoto(data: Data, maximumPixelSize: CGFloat = 1_024) throws -> URL {
        guard let sourceImage = UIImage(data: data), maximumPixelSize > 0 else {
            throw BlessingError.cameraUnavailable
        }
        let pixelWidth = CGFloat(sourceImage.cgImage?.width ?? Int(sourceImage.size.width * sourceImage.scale))
        let pixelHeight = CGFloat(sourceImage.cgImage?.height ?? Int(sourceImage.size.height * sourceImage.scale))
        let longestSide = max(pixelWidth, pixelHeight)
        let scale = min(1, maximumPixelSize / max(longestSide, 1))
        let targetSize = CGSize(
            width: max(1, (pixelWidth * scale).rounded()),
            height: max(1, (pixelHeight * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpegData = resized.jpegData(compressionQuality: 0.78) else {
            throw BlessingError.cameraUnavailable
        }
        let destinationURL = try newRecordingURL(pathExtension: "jpg")
        try jpegData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func persistCroppedProfilePhoto(
        image: UIImage,
        viewportSize: CGFloat,
        zoom: CGFloat,
        offset: CGSize,
        outputPixelSize: CGFloat = 1_024
    ) throws -> URL {
        guard viewportSize > 0,
              zoom >= 1,
              outputPixelSize > 0,
              image.size.width > 0,
              image.size.height > 0 else {
            throw BlessingError.cameraUnavailable
        }

        let fillScale = max(viewportSize / image.size.width, viewportSize / image.size.height)
        let drawSize = CGSize(
            width: image.size.width * fillScale * zoom,
            height: image.size.height * fillScale * zoom
        )
        let maxX = max(0, (drawSize.width - viewportSize) / 2)
        let maxY = max(0, (drawSize.height - viewportSize) / 2)
        let clampedOffset = CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
        let outputScale = outputPixelSize / viewportSize
        let drawRect = CGRect(
            x: ((viewportSize - drawSize.width) / 2 + clampedOffset.width) * outputScale,
            y: ((viewportSize - drawSize.height) / 2 + clampedOffset.height) * outputScale,
            width: drawSize.width * outputScale,
            height: drawSize.height * outputScale
        )
        let outputSize = CGSize(width: outputPixelSize, height: outputPixelSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let cropped = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: drawRect)
        }
        guard let jpegData = cropped.jpegData(compressionQuality: 0.82) else {
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
