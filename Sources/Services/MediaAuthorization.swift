@preconcurrency import AVFoundation
@preconcurrency import Speech

enum MediaAuthorization {
    static func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    static func requestSpeechRecognitionAccess() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
