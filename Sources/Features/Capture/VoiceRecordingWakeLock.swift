import UIKit

@MainActor
enum VoiceRecordingWakeLock {
    private static var owners: Set<UUID> = []
    private static var previousValue: Bool?

    static func setRecording(_ recording: Bool, owner: UUID) {
        if recording {
            if owners.isEmpty { previousValue = UIApplication.shared.isIdleTimerDisabled }
            owners.insert(owner)
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            owners.remove(owner)
            if owners.isEmpty, let previousValue {
                UIApplication.shared.isIdleTimerDisabled = previousValue
                self.previousValue = nil
            }
        }
    }
}
