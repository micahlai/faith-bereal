import Foundation

enum MediaRetentionPolicy {
    static let lifetime: TimeInterval = 14 * 24 * 60 * 60
    static let warningWindow: TimeInterval = 2 * 24 * 60 * 60

    static func expiresAt(submittedAt: Date) -> Date { submittedAt.addingTimeInterval(lifetime) }

    static func isExpired(submittedAt: Date, at now: Date = .now) -> Bool {
        now >= expiresAt(submittedAt: submittedAt)
    }

    static func warning(for submittedAt: Date, at now: Date = .now) -> String? {
        let remaining = expiresAt(submittedAt: submittedAt).timeIntervalSince(now)
        guard remaining > 0, remaining <= warningWindow else { return nil }
        let hours = max(1, Int(ceil(remaining / 3_600)))
        return hours > 24 ? "Media expires in 2 days" : "Media expires in \(hours)h"
    }
}

extension Blessing {
    func replacingMedia(audio: URL?, video: URL?, photo: URL?) -> Blessing {
        Blessing(
            id: id, circleID: circleID, promptID: promptID, authorID: authorID,
            captureMode: captureMode, body: body, audioURL: audio, videoURL: video,
            submittedAt: submittedAt, isLate: isLate, scriptureReference: scriptureReference,
            repeatedFromBlessingID: repeatedFromBlessingID, photoURL: photo, editedAt: editedAt
        )
    }
}

extension BlessingResponse {
    func replacingAudio(_ url: URL?) -> BlessingResponse {
        BlessingResponse(
            id: id, blessingID: blessingID, circleID: circleID, authorID: authorID,
            mode: mode, body: body, audioURL: url, submittedAt: submittedAt
        )
    }
}
