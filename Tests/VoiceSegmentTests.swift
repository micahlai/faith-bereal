import XCTest
import AVFoundation
@testable import BlessingCircle

final class VoiceSegmentTests: XCTestCase {
    func testCombiningSegmentsRetainsBothDurationsAndSupportsDifferentRoutes() async throws {
        var urls: [URL] = []
        for rate in [16_000.0, 44_100.0] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 4)))
            buffer.frameLength = buffer.frameCapacity
            for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][i] = Float(sin(Double(i) * 0.1)) * 0.1 }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            urls.append(url)
        }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
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
