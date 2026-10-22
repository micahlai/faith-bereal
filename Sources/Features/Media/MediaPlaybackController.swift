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
    private(set) var videoAspectRatio: CGFloat = 16 / 9
    private(set) var isPlaying = false
    private(set) var isPreparing = false
    private(set) var errorMessage: String?

    private var url: URL
    private let kind: MediaPlaybackKind
    private let downloader: @Sendable (URL) async throws -> (URL, URLResponse)
    private let diagnostics: BackendDiagnostics
    private var generation = UUID()
    private var recordedPlayerFailure = false
    private var timeObserver: Any?
    private var hasPrepared = false
    private var cachedVoiceURL: URL?
    var cacheAccountID: UUID?
    private let mediaCache: MediaDownloadCache

    init(url: URL, kind: MediaPlaybackKind,
         downloader: @escaping @Sendable (URL) async throws -> (URL, URLResponse) = { try await URLSession.shared.download(from: $0) },
         diagnostics: BackendDiagnostics = .shared, mediaCache: MediaDownloadCache = .shared) {
        self.url = url
        self.kind = kind
        self.downloader = downloader
        self.diagnostics = diagnostics
        self.mediaCache = mediaCache
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main,
            using: MediaPlaybackCallbackFactory.makeTimeObserver { [weak self] time in
                self?.updatePlaybackState(at: time)
            }
        )
    }

    func updateURL(_ url: URL) {
        guard self.url != url else { return }
        generation = UUID()
        self.url = url
        pause()
        player.replaceCurrentItem(with: nil)
        removeCachedVoiceFile()
        hasPrepared = false
        recordedPlayerFailure = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        isPreparing = false
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        isPreparing = true
        errorMessage = nil
        let operation = generation
        var loadingAsset = false

        do {
            let resolvedURL = try await playbackURL(generation: operation)
            try Task.checkCancellation()
            guard generation == operation else { return }
            loadingAsset = true
            let asset = AVURLAsset(url: resolvedURL)
            let playable = try await asset.load(.isPlayable)
            guard playable else {
                throw MediaPlaybackError.unplayable
            }
            if kind == .video,
               let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                try Task.checkCancellation()
                guard generation == operation else { return }
                let presentationSize = naturalSize.applying(transform)
                let width = abs(presentationSize.width)
                let height = abs(presentationSize.height)
                if width > 0, height > 0 {
                    videoAspectRatio = width / height
                }
            }
            try Task.checkCancellation()
            guard generation == operation else { return }
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            let loadedDuration = try? await asset.load(.duration)
            try Task.checkCancellation()
            guard generation == operation else { return }
            if let loadedDuration {
                let seconds = loadedDuration.seconds
                duration = seconds.isFinite && seconds > 0 ? seconds : 0
            }
            isPreparing = false
        } catch {
            guard generation == operation else { return }
            if Self.isCancellation(error) || Task.isCancelled {
                hasPrepared = false
                isPreparing = false
                return
            }
            if loadingAsset { diagnostics.recordFailure(.audio, error: error) }
            isPreparing = false
            if let status = Self.httpStatus(error), [401, 403, 404].contains(status) {
                errorMessage = "This recording’s link is no longer available. Refresh the page and try again."
            } else {
                errorMessage = "This recording couldn’t be loaded. Try opening it again."
            }
        }
    }

    func togglePlayback() async {
        let operation = generation
        if !hasPrepared { await prepare() }
        guard generation == operation, !Task.isCancelled, hasPrepared,
              !isPreparing, player.currentItem != nil, errorMessage == nil else { return }
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
            guard generation == operation, !Task.isCancelled, player.currentItem != nil else { return }
            player.play()
            isPlaying = true
        } catch {
            diagnostics.recordFailure(.audio, error: error)
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
        let operation = generation
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        await player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        guard generation == operation, !Task.isCancelled else { return }
        currentTime = target
    }

    func retry() async {
        let previousGeneration = generation
        if let accountID = cacheAccountID, !url.isFileURL {
            await mediaCache.remove(for: url, accountID: accountID)
        }
        guard generation == previousGeneration else { return }
        generation = UUID()
        hasPrepared = false
        recordedPlayerFailure = false
        pause()
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
            if !recordedPlayerFailure, let failure = player.currentItem?.error {
                recordedPlayerFailure = true
                diagnostics.recordFailure(.audio, error: failure)
            }
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

    private func playbackURL(generation operation: UUID) async throws -> URL {
        if let cachedVoiceURL { return cachedVoiceURL }
        if url.isFileURL {
            // Older archives named CAF files .data. AVURLAsset does not recognize
            // those URLs; stage the same local bytes with their actual container.
            guard url.pathExtension.lowercased() == "data" else { return url }
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                guard try handle.read(upToCount: 4) == Data("caff".utf8) else { return url }
                let local = try CaptureMediaStore.newRecordingURL(pathExtension: "caf")
                do { try FileManager.default.copyItem(at: url, to: local) }
                catch { try? FileManager.default.removeItem(at: local); throw error }
                cachedVoiceURL = local
                return local
            } catch {
                diagnostics.recordFailure(.audio, error: error)
                throw error
            }
        }

        let sourceURL = url
        let accountID = cacheAccountID
        let downloader = self.downloader
        let diagnostics = self.diagnostics
        let measuredDownload: MediaDownloadCache.Download = { source in
            let request = diagnostics.beginRequest(.storageOther)
            do {
                let (file, response) = try await downloader(source)
                let status = (response as? HTTPURLResponse)?.statusCode
                guard let status, (200..<300).contains(status) else {
                    let failure = MediaPlaybackError.httpStatus(status ?? 0)
                    request.finish(httpStatus: status, error: failure)
                    try? FileManager.default.removeItem(at: file)
                    throw failure
                }
                let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                request.finish(httpStatus: status, receivedBytes: bytes.map(Int64.init))
                return (file, response)
            } catch {
                request.finish(error: error)
                throw error
            }
        }
        do {
            let downloaded: URL
            if let accountID {
                downloaded = try await mediaCache.file(for: sourceURL, accountID: accountID, download: measuredDownload)
            } else {
                let (temporary, response) = try await measuredDownload(sourceURL)
                guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw MediaPlaybackError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                downloaded = temporary
            }
            defer { if accountID == nil { try? FileManager.default.removeItem(at: downloaded) } }
            try Task.checkCancellation()
            guard generation == operation else { throw CancellationError() }
            let ext = sourceURL.pathExtension.lowercased()
            let localURL = try CaptureMediaStore.newRecordingURL(pathExtension:
                ["m4a", "caf", "mp4", "mov"].contains(ext) ? ext : kind == .video ? "mp4" : "caf")
            try FileManager.default.copyItem(at: downloaded, to: localURL)
            cachedVoiceURL = localURL
            return localURL
        } catch { throw error }
    }

    private func removeCachedVoiceFile() {
        guard let cachedVoiceURL else { return }
        try? FileManager.default.removeItem(at: cachedVoiceURL)
        self.cachedVoiceURL = nil
    }

    private static func httpStatus(_ error: any Error) -> Int? {
        if case let MediaPlaybackError.httpStatus(status) = error { return status }
        if case let MediaDownloadError.httpStatus(status) = error { return status }
        return nil
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        let ns = error as NSError
        return error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
    }
}

private enum MediaPlaybackError: Error {
    case unplayable
    case httpStatus(Int)
}
