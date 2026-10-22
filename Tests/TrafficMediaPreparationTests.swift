import XCTest
import AVFoundation
import UIKit
@testable import BlessingCircle

@MainActor
final class TrafficMediaPreparationTests: XCTestCase {
    func testPhotoPreviewIsSmallAndDoesNotReplaceOriginal() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        }
        let original = try CaptureMediaStore.persistPhoto(data: XCTUnwrap(image.jpegData(compressionQuality: 0.9)))
        let preview = try CaptureMediaStore.persistPhotoPreview(from: original)
        defer { try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: preview) }
        let full = try XCTUnwrap(UIImage(contentsOfFile: original.path)?.cgImage)
        let small = try XCTUnwrap(UIImage(contentsOfFile: preview.path)?.cgImage)
        XCTAssertEqual(full.width, 2400)
        XCTAssertLessThanOrEqual(max(small.width, small.height), 480)
        XCTAssertLessThan(try Data(contentsOf: preview).count, try Data(contentsOf: original).count)
    }

    func testVideoExportCapsResolutionPreservesDurationAndLeavesSourceIntact() async throws {
        let source = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let output = try await CaptureMediaStore.compressedVideo(from: source)
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertEqual(output.pathExtension, "mp4")
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1280)
        XCTAssertLessThanOrEqual(min(size.width, size.height), 720)
        let duration = try await asset.load(.duration).seconds
        let originalDuration = try await AVURLAsset(url: source).load(.duration).seconds
        XCTAssertEqual(duration, originalDuration, accuracy: 0.08)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
    }

    func testFailedVideoExportDoesNotDeleteDraftSource() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try Data("invalid movie".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        do { _ = try await CaptureMediaStore.compressedVideo(from: source); XCTFail("Exported corrupt movie") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 1920, kCVPixelBufferHeightKey as String: 1080])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<6 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixel = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), Int32(index * 20), CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 15)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
