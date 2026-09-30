import AVFoundation
import Observation
import Speech

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
        recordedAudioFile = nil
        deactivateAudioSession()
        state = .idle
    }

    func reset() {
        stop()
        transcript = ""
        recordingURL = nil
    }

    func transcribeVideo(at url: URL) async -> String? {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized, let recognizer, recognizer.isAvailable else { return nil }

        task?.cancel()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            fileContinuation = continuation
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result, result.isFinal {
                        self.finishFileTranscription(with: result.bestTranscription.formattedString)
                    } else if error != nil {
                        self.finishFileTranscription(with: nil)
                    }
                }
            }
        }
    }

    private func requestPermissionAndStart() async {
        state = .requestingPermission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
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
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            state = .failed("The microphone could not be started. Check audio access and try again.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
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
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            request.append(buffer)
            try? audioFile.write(from: buffer)
        }
        hasInputTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let sessionID = UUID()
        recognitionSessionID = sessionID
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.recognitionSessionID == sessionID else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self.stop()
                    self.state = .failed(error.localizedDescription)
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishFileTranscription(with text: String?) {
        guard let continuation = fileContinuation else { return }
        fileContinuation = nil
        task = nil
        continuation.resume(returning: text)
    }
}
