import AVFoundation
import XCTest
@testable import BlessingCircle

final class MediaPlaybackTests: XCTestCase {
    @MainActor
    func testCancelledInitialPlayDoesNotStartAnEmptyPlayer() async throws {
        let fixture = PlaybackDownloadFixture(cancelFirst: true)
        defer { fixture.cleanup() }
        let playback = MediaPlaybackController(url: URL(string: "https://example.invalid/cancel-play")!,
            kind: .voice, downloader: fixture.download, diagnostics: BackendDiagnostics(enabled: false))
        await playback.togglePlayback()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.isPreparing)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertNil(playback.errorMessage)
    }

    @MainActor
    func testHTTPFailuresPreserveStatusWithoutUploadingSignedURL() async throws {
        for status in [403, 503] {
            let recorder = PlaybackEventRecorder()
            let diagnostics = BackendDiagnostics(enabled: true, sink: recorder.append)
            let fixture = PlaybackDownloadFixture(status: status)
            defer { fixture.cleanup() }
            let url = URL(string: "https://private.invalid/recording?token=private-signed-token")!
            let playback = MediaPlaybackController(url: url, kind: .voice,
                downloader: fixture.download, diagnostics: diagnostics)
            await playback.prepare()
            XCTAssertFalse(playback.isPreparing)
            XCTAssertNotNil(playback.errorMessage)
            XCTAssertNil(playback.player.currentItem)
            let event = try XCTUnwrap(recorder.events.first { $0.requestKind == .storageOther })
            XCTAssertEqual(event.outcome, .failure)
            XCTAssertEqual(event.httpStatus, status)
            let serialized = String(decoding: try JSONEncoder().encode(recorder.events), as: UTF8.self)
            for privateValue in ["private.invalid", "recording?", "private-signed-token"] {
                XCTAssertFalse(serialized.contains(privateValue))
            }
        }
    }

    @MainActor
    func testCancelledDownloadDoesNotShowAnErrorAndCanRetry() async throws {
        let fixture = PlaybackDownloadFixture(cancelFirst: true)
        defer { fixture.cleanup() }
        let recorder = PlaybackEventRecorder()
        let url = URL(string: "https://example.invalid/cancel-once")!
        let playback = MediaPlaybackController(url: url, kind: .voice,
            downloader: fixture.download, diagnostics: BackendDiagnostics(enabled: true, sink: recorder.append))
        await playback.prepare()
        XCTAssertFalse(playback.isPreparing)
        XCTAssertNil(playback.errorMessage)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertEqual(recorder.events.first { $0.requestKind == .storageOther }?.outcome, .cancelled)
        await playback.retry()
        XCTAssertFalse(playback.isPreparing)
        XCTAssertNil(playback.errorMessage)
        XCTAssertNotNil(playback.player.currentItem)
        XCTAssertGreaterThan(playback.duration, 0)
        XCTAssertEqual(fixture.urls.count, 2)
        playback.updateURL(URL(string: "https://example.invalid/cleanup")!)
    }

    @MainActor
    func testUpdatedSignedURLInvalidatesCachedVoiceAndRetryUsesLatestURL() async throws {
        let fixture = PlaybackDownloadFixture()
        defer { fixture.cleanup() }
        let original = URL(string: "https://example.invalid/recording?token=old")!
        let replacement = URL(string: "https://example.invalid/recording?token=fresh")!
        let playback = MediaPlaybackController(url: original, kind: .voice,
            downloader: fixture.download, diagnostics: BackendDiagnostics(enabled: false))
        await playback.prepare()
        XCTAssertNotNil(playback.player.currentItem)
        playback.updateURL(replacement)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertNil(playback.errorMessage)
        await playback.retry()
        XCTAssertNil(playback.errorMessage)
        XCTAssertNotNil(playback.player.currentItem)
        XCTAssertEqual(fixture.urls, [original, replacement])
        playback.updateURL(URL(string: "https://example.invalid/cleanup")!)
    }

    @MainActor
    func testOldDownloadFailureCannotOverwriteReplacementPlayback() async throws {
        let fixture = PlaybackDownloadFixture()
        defer { fixture.cleanup() }
        let gate = PlaybackDownloadGate()
        let original = URL(string: "https://example.invalid/old")!
        let replacement = URL(string: "https://example.invalid/new")!
        let playback = MediaPlaybackController(url: original, kind: .voice, downloader: { url in
            if url == original {
                await gate.hold()
                throw URLError(.timedOut)
            }
            return try await fixture.download(url)
        }, diagnostics: BackendDiagnostics(enabled: false))
        let oldPreparation = Task { await playback.prepare() }
        await gate.waitUntilStarted()
        playback.updateURL(replacement)
        await playback.prepare()
        let newItem = try XCTUnwrap(playback.player.currentItem)
        await gate.release()
        await oldPreparation.value
        XCTAssertTrue(playback.player.currentItem === newItem)
        XCTAssertNil(playback.errorMessage)
        XCTAssertFalse(playback.isPreparing)
        XCTAssertGreaterThan(playback.duration, 0)
        playback.updateURL(URL(string: "https://example.invalid/cleanup")!)
    }

    @MainActor
    func testOldSuccessfulDownloadCannotReplaceTheNewPlayerItem() async throws {
        let fixture = PlaybackDownloadFixture()
        defer { fixture.cleanup() }
        let gate = PlaybackDownloadGate()
        let original = URL(string: "https://example.invalid/old-success")!
        let replacement = URL(string: "https://example.invalid/new-success")!
        let playback = MediaPlaybackController(url: original, kind: .voice, downloader: { url in
            if url == original { await gate.hold() }
            return try await fixture.download(url)
        }, diagnostics: BackendDiagnostics(enabled: false))
        let oldPreparation = Task { await playback.prepare() }
        await gate.waitUntilStarted()
        playback.updateURL(replacement)
        await playback.prepare()
        let newItem = try XCTUnwrap(playback.player.currentItem)
        await gate.release()
        await oldPreparation.value
        XCTAssertTrue(playback.player.currentItem === newItem)
        XCTAssertNil(playback.errorMessage)
        XCTAssertFalse(playback.isPreparing)
        playback.updateURL(URL(string: "https://example.invalid/cleanup")!)
    }

    @MainActor
    func testRemoteM4AAACRecordingKeepsItsContainerExtensionAndPrepares() async throws {
        let fixture = PlaybackDownloadFixture(container: "m4a")
        defer { fixture.cleanup() }
        let url = URL(string: "https://example.invalid/voice.m4a?token=synthetic")!
        let playback = MediaPlaybackController(url: url, kind: .voice,
            downloader: fixture.download, diagnostics: BackendDiagnostics(enabled: false))
        await playback.prepare()
        XCTAssertNil(playback.errorMessage)
        XCTAssertFalse(playback.isPreparing)
        XCTAssertGreaterThan(playback.duration, 0)
        let asset = try XCTUnwrap(playback.player.currentItem?.asset as? AVURLAsset)
        XCTAssertEqual(asset.url.pathExtension, "m4a")
        playback.updateURL(URL(string: "https://example.invalid/cleanup")!)
    }

    @MainActor
    func testUnplayableDownloadedBytesRecordAssetFailure() async throws {
        let recorder = PlaybackEventRecorder()
        let fixture = PlaybackDownloadFixture(validRecording: false)
        defer { fixture.cleanup() }
        let playback = MediaPlaybackController(url: URL(string: "https://example.invalid/invalid-asset")!,
            kind: .voice, downloader: fixture.download,
            diagnostics: BackendDiagnostics(enabled: true, sink: recorder.append))
        await playback.prepare()
        XCTAssertNotNil(playback.errorMessage)
        XCTAssertFalse(playback.isPreparing)
        XCTAssertEqual(recorder.events.filter { $0.requestKind == .storageOther && $0.outcome == .success }.count, 1)
        XCTAssertEqual(recorder.events.filter { $0.requestKind == .audio && $0.outcome == .failure }.count, 1)
        playback.updateURL(URL(string: "https://example.invalid/cleanup")!)
    }
}

private final class PlaybackEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [BackendDiagnostics.Event] = []
    var events: [BackendDiagnostics.Event] { lock.withLock { stored } }
    func append(_ event: BackendDiagnostics.Event) { lock.withLock { stored.append(event) } }
}

private final class PlaybackDownloadFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var requestedURLs: [URL] = []
    private var temporaryFiles: [URL] = []
    private let status: Int
    private let cancelFirst: Bool
    private let validRecording: Bool
    private let container: String
    var urls: [URL] { lock.withLock { requestedURLs } }

    init(status: Int = 200, cancelFirst: Bool = false, validRecording: Bool = true, container: String = "caf") {
        self.status = status
        self.cancelFirst = cancelFirst
        self.validRecording = validRecording
        self.container = container
    }

    func download(_ url: URL) async throws -> (URL, URLResponse) {
        let attempt = lock.withLock { requestedURLs.append(url); return requestedURLs.count }
        if cancelFirst && attempt == 1 { throw URLError(.cancelled) }
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + container)
        lock.withLock { temporaryFiles.append(temporaryURL) }
        if validRecording {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
            let settings: [String: Any] = container == "m4a"
                ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                   AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
                : format.settings
            let file = try AVAudioFile(forWriting: temporaryURL, settings: settings,
                commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
            buffer.frameLength = 4_410
            try file.write(from: buffer)
        } else {
            try Data("Invalid recording bytes".utf8).write(to: temporaryURL)
        }
        return (temporaryURL, try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: nil)))
    }

    func cleanup() {
        for url in lock.withLock({ temporaryFiles }) { try? FileManager.default.removeItem(at: url) }
    }
}

private actor PlaybackDownloadGate {
    private var started = false
    private var starter: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    func hold() async {
        started = true
        starter?.resume()
        starter = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { starter = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
