import AVFoundation
import Foundation

enum VoiceSegmentAssembler {
    enum Failure: Error { case missingAudio }
    static func combine(_ segments: [URL]) async throws -> URL {
        guard !segments.isEmpty else { throw Failure.missingAudio }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.missingAudio
        }
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw Failure.missingAudio
            }
            let duration = try await asset.load(.duration)
            guard duration.isNumeric, duration.seconds > 0 else { throw Failure.missingAudio }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = cursor + duration
        }
        let output = try CaptureMediaStore.newRecordingURL(pathExtension: "m4a")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.missingAudio
        }
        do {
            try Task.checkCancellation()
            try await exporter.export(to: output, as: .m4a)
            try Task.checkCancellation()
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
