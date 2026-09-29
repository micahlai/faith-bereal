import Foundation

struct Member: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var initials: String
    var tintSeed: Int
}

struct Circle: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var inviteCode: String
    var members: [Member]
    var timeZoneIdentifier: String
}

struct DailyPrompt: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let circleID: UUID
    let localDate: Date
    let startsAt: Date
    let endsAt: Date

    func phase(at date: Date) -> PromptPhase {
        if date < startsAt { return .scheduled }
        if date < endsAt { return .open }
        return .closed
    }
}

enum PromptPhase: String, Codable, Sendable {
    case scheduled
    case open
    case closed
}

enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case typed
    case voice
    case video

    var id: Self { self }

    var title: String {
        switch self {
        case .typed: "Type"
        case .voice: "Speak"
        case .video: "Video"
        }
    }

    var systemImage: String {
        switch self {
        case .typed: "text.cursor"
        case .voice: "waveform"
        case .video: "video"
        }
    }
}

struct Blessing: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let promptID: UUID
    let authorID: UUID
    let captureMode: CaptureMode
    let body: String?
    let videoURL: URL?
    let submittedAt: Date
}

enum TimelineStatus: Hashable, Sendable {
    case blessing(Blessing)
    case missed
    case locked
    case waiting
}

struct TimelineEvent: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let status: TimelineStatus

    init(memberID: UUID, date: Date, status: TimelineStatus) {
        self.id = "\(memberID.uuidString)-\(date.timeIntervalSince1970)"
        self.date = date
        self.status = status
    }
}

struct TimelineLane: Identifiable, Hashable, Sendable {
    let member: Member
    let events: [TimelineEvent]
    var id: UUID { member.id }
}

enum VisibilityPolicy {
    static func canReadPeerBlessing(
        promptDate: Date,
        now: Date,
        viewerHasSubmitted: Bool,
        calendar: Calendar
    ) -> Bool {
        if !calendar.isDate(promptDate, inSameDayAs: now) { return true }
        return viewerHasSubmitted
    }
}

enum BlessingError: LocalizedError, Equatable {
    case invalidInviteCode
    case emptyBlessing
    case outsideResponseWindow
    case alreadySubmitted
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode: "That circle code was not found. Check it and try again."
        case .emptyBlessing: "Add a thought or record a video before sending."
        case .outsideResponseWindow: "The ten-minute response window has closed."
        case .alreadySubmitted: "You already shared a blessing for this prompt."
        case .cameraUnavailable: "The camera is not available on this device."
        }
    }
}

