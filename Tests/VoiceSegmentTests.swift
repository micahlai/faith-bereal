import XCTest
import AVFoundation
@testable import BlessingCircle

final class VoiceSegmentTests: XCTestCase {
    func testCombiningSegmentsRetainsBothDurationsAndSupportsDifferentRoutes() async throws {
        var urls: [URL] = []
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        for rate in [16_000.0, 44_100.0] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            urls.append(url)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 4)))
            buffer.frameLength = buffer.frameCapacity
            for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][i] = Float(sin(Double(i) * 0.1)) * 0.1 }
            try autoreleasepool {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            let sourceFile = try AVAudioFile(forReading: url)
            XCTAssertEqual(Double(sourceFile.length) / sourceFile.fileFormat.sampleRate, 0.25,
                accuracy: 0.001, "The synthetic route segment must be finalized before assembly.")
            let sourceDuration = try await AVURLAsset(url: url).load(.duration).seconds
            XCTAssertEqual(sourceDuration, 0.25, accuracy: 0.001,
                "The asset must report the same duration as its source sample frames at \(rate) Hz.")
        }
        let output = try await VoiceSegmentAssembler.combine(urls)
        defer { try? FileManager.default.removeItem(at: output) }
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        XCTAssertEqual(output.pathExtension, "m4a")
        XCTAssertEqual(duration, 0.5, accuracy: 0.06)
        let single = try await VoiceSegmentAssembler.combine([urls[0]])
        XCTAssertEqual(single, urls[0])
    }

    @MainActor
    func testResetInvalidatesPendingPermissionAndRecordingState() async {
        let recorder = SpeechTranscriber()
        recorder.transcript = "Edited words"
        recorder.reset()
        XCTAssertEqual(recorder.transcript, "")
        XCTAssertEqual(recorder.state, .idle)
        let audio = await recorder.finishRecording()
        XCTAssertNil(audio)
    }
}
