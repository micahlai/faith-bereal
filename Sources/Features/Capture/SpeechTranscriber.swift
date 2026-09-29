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

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if state == .listening {
            stop()
        } else {
            await requestPermissionAndStart()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        state = .idle
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
        start()
    }

    private func start() {
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self?.stop()
                    self?.state = .failed(error.localizedDescription)
                } else if result?.isFinal == true {
                    self?.stop()
                }
            }
        }
    }
}

