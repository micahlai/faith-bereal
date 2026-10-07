import AVFoundation
import Observation

enum MediaPlaybackKind {
    case voice
    case video
}

enum MediaTimeFormatter {
    static func string(for seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let wholeSeconds = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

private enum MediaPlaybackCallbackFactory {
    nonisolated static func makeTimeObserver(
        _ callback: @escaping @MainActor @Sendable (CMTime) -> Void
    ) -> @Sendable (CMTime) -> Void {
        { time in
            Task { @MainActor in callback(time) }
        }
    }
}

@MainActor
@Observable
final class MediaPlaybackController {
    let player = AVPlayer()
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isPreparing = true
    private(set) var errorMessage: String?

    private let url: URL
    private let kind: MediaPlaybackKind
    private var timeObserver: Any?
    private var hasPrepared = false
    private var cachedVoiceURL: URL?

    init(url: URL, kind: MediaPlaybackKind) {
        self.url = url
        self.kind = kind
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main,
            using: MediaPlaybackCallbackFactory.makeTimeObserver { [weak self] time in
                self?.updatePlaybackState(at: time)
            }
        )
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        isPreparing = true
        errorMessage = nil

        do {
            let resolvedURL = try await playbackURL()
            try Task.checkCancellation()
            let asset = AVURLAsset(url: resolvedURL)
            let playable = try await asset.load(.isPlayable)
            guard playable else {
                throw MediaPlaybackError.unplayable
            }
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            if let loadedDuration = try? await asset.load(.duration) {
                let seconds = loadedDuration.seconds
                duration = seconds.isFinite && seconds > 0 ? seconds : 0
            }
            isPreparing = false
        } catch is CancellationError {
            hasPrepared = false
            isPreparing = false
        } catch {
            isPreparing = false
            errorMessage = "This recording couldn’t be loaded. Try opening it again."
        }
    }

    func togglePlayback() async {
        if !hasPrepared { await prepare() }
        guard errorMessage == nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }

        do {
            try configureAudioSessionForPlayback()
            if duration > 0, currentTime >= duration - 0.15 {
                await seek(to: 0)
            }
            player.play()
            isPlaying = true
        } catch {
            errorMessage = "Audio playback isn’t available right now."
        }
    }

    func play() async {
        guard !isPlaying else { return }
        await togglePlayback()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) async {
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        await player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
    }

    func retry() async {
        hasPrepared = false
        player.replaceCurrentItem(with: nil)
        removeCachedVoiceFile()
        await prepare()
    }

    private func updatePlaybackState(at time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite, seconds >= 0 { currentTime = seconds }
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite,
           itemDuration > 0 {
            duration = itemDuration
        }
        isPlaying = player.timeControlStatus != .paused
        if player.currentItem?.status == .failed {
            errorMessage = "This recording couldn’t be played. Try opening it again."
            isPreparing = false
        }
    }

    private func configureAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = kind == .video ? .moviePlayback : .spokenAudio
        try session.setCategory(.playback, mode: mode)
        try session.setActive(true)
    }

    private func playbackURL() async throws -> URL {
        guard kind == .voice, !url.isFileURL else { return url }
        if let cachedVoiceURL { return cachedVoiceURL }

        let (downloadURL, response) = try await URLSession.shared.download(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw MediaPlaybackError.downloadFailed
        }
        try Task.checkCancellation()

        let localURL = try CaptureMediaStore.newRecordingURL(pathExtension: "caf")
        do {
            try FileManager.default.moveItem(at: downloadURL, to: localURL)
        } catch {
            try FileManager.default.copyItem(at: downloadURL, to: localURL)
        }
        cachedVoiceURL = localURL
        return localURL
    }

    private func removeCachedVoiceFile() {
        guard let cachedVoiceURL else { return }
        try? FileManager.default.removeItem(at: cachedVoiceURL)
        self.cachedVoiceURL = nil
    }
}

private enum MediaPlaybackError: Error {
    case unplayable
    case downloadFailed
}
