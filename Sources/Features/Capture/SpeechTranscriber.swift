import AVFoundation
import Observation
import Speech

private final class SpeechAudioTapSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let audioFile: AVAudioFile
    private let lock = NSLock()
    private var writeFailure: BackendDiagnosticFailure?

    init(request: SFSpeechAudioBufferRecognitionRequest, audioFile: AVAudioFile) {
        self.request = request
        self.audioFile = audioFile
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        do {
            try audioFile.write(from: buffer)
        } catch {
            lock.lock()
            if writeFailure == nil { writeFailure = BackendDiagnosticFailure.capture(error: error) }
            lock.unlock()
        }
    }

    func recordingFailure() -> BackendDiagnosticFailure? {
        lock.lock()
        defer { lock.unlock() }
        return writeFailure
    }
}

/// The UI message stays local; only the sanitized diagnostic snapshot may be uploaded.
struct SpeechRecognitionCallbackFailure: Sendable {
    let message: String
    let diagnostic: BackendDiagnosticFailure
}

enum SpeechCallbackFactory {
    fileprivate static func makeAudioTap(sink: SpeechAudioTapSink) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink.receive(buffer)
        }
    }

    static func makeRecognitionHandler(
        _ callback: @escaping @MainActor @Sendable (String?, Bool, SpeechRecognitionCallbackFailure?) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            // Capture the underlying NSError before crossing the actor boundary. Passing only
            // localizedDescription would lose the domain/code needed to identify the service.
            let failure = error.map {
                SpeechRecognitionCallbackFailure(message: $0.localizedDescription,
                    diagnostic: BackendDiagnosticFailure.capture(error: $0))
            }
            Task { @MainActor in
                callback(transcript, isFinal, failure)
            }
        }
    }
}

@MainActor
@Observable
final class SpeechTranscriber: NSObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finishing
        case denied
        case failed(String)
    }

    var transcript = ""
    var state: State = .idle {
        didSet { VoiceRecordingWakeLock.setRecording(state == .listening, owner: wakeLockID) }
    }
    private let wakeLockID = UUID()
    private(set) var recordingURL: URL?

    private var audioEngine = AVAudioEngine()
    private static weak var activeRecorder: SpeechTranscriber?
    private var segments: [URL] = []
    private var transcriptPrefix = ""
    private var permissionID: UUID?
    private var assemblyTask: Task<Void, Never>?
    private var assemblyID: UUID?
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var recordedAudioFile: AVAudioFile?
    private var tapSink: SpeechAudioTapSink?
    private var fileContinuation: CheckedContinuation<String?, Never>?
    private var fileRecognitionSessionID: UUID?
    private var recognitionSessionID: UUID?

    func toggle(existingTranscript: String? = nil) async {
        guard state != .requestingPermission, state != .finishing else { return }
        if state == .listening {
            stop()
        } else {
            if let existingTranscript { transcript = existingTranscript }
            await requestPermissionAndStart()
        }
    }

    func stop() {
        permissionID = nil
        let wasListening = state == .listening
        let capturedURL = recordingURL
        let recordingWriteFailure = tapSink?.recordingFailure()
        if let recordingWriteFailure {
            BackendDiagnostics.shared.recordFailure(.audio, failure: recordingWriteFailure)
        }
        recognitionSessionID = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        tapSink = nil
        recordedAudioFile = nil
        deactivateAudioSession()
        if Self.activeRecorder === self { Self.activeRecorder = nil }
        if recordingWriteFailure != nil || capturedURL.map(Self.isEmptyRecording) == true {
            recordingURL = nil
            state = .failed("The microphone started, but the recording could not be saved. Please try again.")
        } else {
            if wasListening, let capturedURL { segments.append(capturedURL) }
            if state != .finishing { state = .idle }
            if wasListening, !segments.isEmpty { assembleSegments() }
        }
    }

    func finishRecording() async -> URL? {
        stop()
        await assemblyTask?.value
        return recordingURL
    }

    var draftAudioSegments: [URL] {
        var result = segments
        if state == .listening, let recordingURL, !result.contains(recordingURL) { result.append(recordingURL) }
        if result.isEmpty, let recordingURL { result.append(recordingURL) }
        return result.filter { !Self.isEmptyRecording($0) }
    }

    func restoreDraftAudio(_ urls: [URL], text: String) {
        reset()
        transcript = text
        segments = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !segments.isEmpty { assembleSegments() }
    }

    private func assembleSegments() {
        let id = UUID()
        assemblyID = id
        let input = segments
        state = .finishing
        assemblyTask = Task { [weak self] in
            do {
                let url = try await VoiceSegmentAssembler.combine(input)
                guard let self, self.assemblyID == id, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                self.recordingURL = url
                self.state = .idle
            } catch {
                guard let self, self.assemblyID == id, !Task.isCancelled else { return }
                BackendDiagnostics.shared.recordFailure(.audio, error: error)
                self.recordingURL = nil
                self.state = .failed("Couldn’t prepare your recording. Try again or start over.")
            }
        }
    }

    func reset() {
        stop()
        assemblyTask?.cancel()
        assemblyID = nil
        segments = []
        transcriptPrefix = ""
        transcript = ""
        recordingURL = nil
        state = .idle
    }

    func transcribeVideo(at url: URL) async -> String? {
        let speechStatus = await MediaAuthorization.requestSpeechRecognitionAccess()
        guard speechStatus == .authorized, let recognizer, recognizer.isAvailable else { return nil }

        task?.cancel()
        let fileSessionID = UUID()
        fileRecognitionSessionID = fileSessionID
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            fileContinuation = continuation
            task = recognizer.recognitionTask(
                with: request,
                resultHandler: SpeechCallbackFactory.makeRecognitionHandler { [weak self] transcript, isFinal, failure in
                    guard let self, self.fileContinuation != nil,
                          self.fileRecognitionSessionID == fileSessionID else { return }
                    if let failure {
                        BackendDiagnostics.shared.recordFailure(.speech, failure: failure.diagnostic)
                    }
                    if isFinal {
                        self.finishFileTranscription(with: transcript)
                    } else if failure != nil {
                        self.finishFileTranscription(with: nil)
                    }
                }
            )
        }
    }

    private func requestPermissionAndStart() async {
        let id = UUID()
        permissionID = id
        state = .requestingPermission
        let speechStatus = await MediaAuthorization.requestSpeechRecognitionAccess()
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard permissionID == id, state == .requestingPermission else { return }
        guard speechStatus == .authorized, microphoneAllowed else {
            state = .denied
            return
        }
        await start()
    }

    private func start() async {
        stop()
        Self.activeRecorder?.stop()
        Self.activeRecorder = self
        transcriptPrefix = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // A stopped engine can retain a poisoned hardware graph after route changes.
        // Every segment owns a fresh engine and at most one input tap.
        audioEngine = AVAudioEngine()
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognition is temporarily unavailable.")
            return
        }

        let sessionSpan = BackendDiagnostics.shared.beginRequest(.audio)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
            sessionSpan.finish()
        } catch {
            sessionSpan.finish(error: error)
            state = .failed("The microphone could not be started. Check audio access and try again.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            deactivateAudioSession()
            state = .failed("No microphone input is available.")
            return
        }

        let outputURL: URL
        let audioFile: AVAudioFile
        let fileSpan = BackendDiagnostics.shared.beginRequest(.audio)
        do {
            outputURL = try CaptureMediaStore.newRecordingURL(pathExtension: "caf")
            audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
            recordedAudioFile = audioFile
            recordingURL = outputURL
            fileSpan.finish()
        } catch {
            fileSpan.finish(error: error)
            recordingURL = nil
            deactivateAudioSession()
            state = .failed("The audio recording could not be created.")
            return
        }
        let tapSink = SpeechAudioTapSink(request: request, audioFile: audioFile)
        self.tapSink = tapSink
        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil,
            block: SpeechCallbackFactory.makeAudioTap(sink: tapSink)
        )
        hasInputTap = true

        audioEngine.prepare()
        let engineSpan = BackendDiagnostics.shared.beginRequest(.audio)
        do {
            try audioEngine.start()
            engineSpan.finish()
            state = .listening
        } catch {
            engineSpan.finish(error: error)
            if hasInputTap {
                input.removeTap(onBus: 0)
                hasInputTap = false
            }
            request.endAudio()
            self.request = nil
            self.tapSink = nil
            recordedAudioFile = nil
            recordingURL = nil
            deactivateAudioSession()
            state = .failed(error.localizedDescription)
            return
        }

        let sessionID = UUID()
        recognitionSessionID = sessionID
        task = recognizer.recognitionTask(
            with: request,
            resultHandler: SpeechCallbackFactory.makeRecognitionHandler { [weak self] transcript, isFinal, failure in
                guard let self else { return }
                guard self.recognitionSessionID == sessionID else { return }
                if let transcript {
                    self.transcript = [self.transcriptPrefix, transcript].filter { !$0.isEmpty }.joined(separator: " ")
                }
                if let failure {
                    BackendDiagnostics.shared.recordFailure(.speech, failure: failure.diagnostic)
                    self.stop()
                    self.state = .failed(failure.message)
                } else if isFinal {
                    self.stop()
                }
            }
        )
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            BackendDiagnostics.shared.recordFailure(.audio, error: error)
        }
    }

    private static func isEmptyRecording(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return true }
        return fileSize < 512
    }

    private func finishFileTranscription(with text: String?) {
        guard let continuation = fileContinuation else { return }
        fileContinuation = nil
        fileRecognitionSessionID = nil
        task = nil
        continuation.resume(returning: text)
    }
}
