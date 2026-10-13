import XCTest
import UIKit
@testable import BlessingCircle

final class VoiceWakeLockTests: XCTestCase {
    @MainActor
    func testOnlyLastRecorderRestoresPreviousSleepSetting() {
        let original = UIApplication.shared.isIdleTimerDisabled
        defer { UIApplication.shared.isIdleTimerDisabled = original }
        UIApplication.shared.isIdleTimerDisabled = false
        let a = UUID(), b = UUID()
        VoiceRecordingWakeLock.setRecording(true, owner: a)
        VoiceRecordingWakeLock.setRecording(true, owner: b)
        VoiceRecordingWakeLock.setRecording(false, owner: a)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        VoiceRecordingWakeLock.setRecording(false, owner: b)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        VoiceRecordingWakeLock.setRecording(false, owner: a)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        XCTAssertTrue(HelpTopic.sharing.steps.map(\.body).joined().contains("phone stays awake"))
    }
}
