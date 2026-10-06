import AVFoundation
import Observation
import Speech

private final class SpeechAudioTapSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let audioFile: AVAudioFile
    private let lock = NSLock()
    private var writeFailed = false

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
            writeFailed = true
            lock.unlock()
        }
    }

    func hasWriteFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return writeFailed
    }
}

private enum SpeechCallbackFactory {
    static func makeAudioTap(sink: SpeechAudioTapSink) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink.receive(buffer)
        }
    }

    static func makeRecognitionHandler(
        _ callback: @escaping @MainActor @Sendable (String?, Bool, String?) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                callback(transcript, isFinal, errorMessage)
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
        case denied
        case failed(String)
    }

    var transcript = ""
    var state: State = .idle
    private(set) var recordingURL: URL?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var recordedAudioFile: AVAudioFile?
    private var tapSink: SpeechAudioTapSink?
    private var fileContinuation: CheckedContinuation<String?, Never>?
    private var recognitionSessionID: UUID?

    func toggle() async {
        if state == .listening {
            stop()
        } else {
            await requestPermissionAndStart()
        }
    }

    func stop() {
        let capturedURL = recordingURL
        let recordingWriteFailed = tapSink?.hasWriteFailure() == true
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
        if recordingWriteFailed || capturedURL.map(Self.isEmptyRecording) == true {
            recordingURL = nil
            state = .failed("The microphone started, but the recording could not be saved. Please try again.")
        } else {
            state = .idle
        }
    }

    func reset() {
        stop()
        transcript = ""
        recordingURL = nil
    }

    func transcribeVideo(at url: URL) async -> String? {
        let speechStatus = await MediaAuthorization.requestSpeechRecognitionAccess()
        guard speechStatus == .authorized, let recognizer, recognizer.isAvailable else { return nil }

        task?.cancel()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            fileContinuation = continuation
            task = recognizer.recognitionTask(
                with: request,
                resultHandler: SpeechCallbackFactory.makeRecognitionHandler { [weak self] transcript, isFinal, errorMessage in
                    guard let self else { return }
                    if isFinal {
                        self.finishFileTranscription(with: transcript)
                    } else if errorMessage != nil {
                        self.finishFileTranscription(with: nil)
                    }
                }
            )
        }
    }

    private func requestPermissionAndStart() async {
        state = .requestingPermission
        let speechStatus = await MediaAuthorization.requestSpeechRecognitionAccess()
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechStatus == .authorized, microphoneAllowed else {
            state = .denied
            return
        }
        await start()
    }

    private func start() async {
        stop()
        transcript = ""
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognition is temporarily unavailable.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
        } catch {
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
        do {
            outputURL = try CaptureMediaStore.newRecordingURL(pathExtension: "caf")
            audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
            recordedAudioFile = audioFile
            recordingURL = outputURL
        } catch {
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
            format: format,
            block: SpeechCallbackFactory.makeAudioTap(sink: tapSink)
        )
        hasInputTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .listening
        } catch {
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
            resultHandler: SpeechCallbackFactory.makeRecognitionHandler { [weak self] transcript, isFinal, errorMessage in
                guard let self else { return }
                guard self.recognitionSessionID == sessionID else { return }
                if let transcript {
                    self.transcript = transcript
                }
                if let errorMessage {
                    self.stop()
                    self.state = .failed(errorMessage)
                } else if isFinal {
                    self.stop()
                }
            }
        )
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func isEmptyRecording(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return true }
        return fileSize < 512
    }

    private func finishFileTranscription(with text: String?) {
        guard let continuation = fileContinuation else { return }
        fileContinuation = nil
        task = nil
        continuation.resume(returning: text)
    }
}
