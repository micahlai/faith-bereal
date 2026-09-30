import Foundation

struct AppBootstrap: Sendable {
    let currentUser: Member
    let circles: [CircleGroup]
    let selectedCircleID: UUID?
    let prompt: DailyPrompt?

    var circle: CircleGroup? {
        guard let selectedCircleID else { return nil }
        return circles.first { $0.id == selectedCircleID }
    }
}

struct CircleContext: Sendable {
    let circle: CircleGroup
    let prompt: DailyPrompt?
}

struct Member: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var initials: String
    var tintSeed: Int
    var bibleVersionID: String = "web"
    var joinedAt: Date = .distantPast
}

struct CircleGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var inviteCode: String
    var ownerID: UUID
    var members: [Member]
    var timeZoneIdentifier: String
    var randomWindowStartMinutes: Int
    var randomWindowEndMinutes: Int
    var responseWindowMinutes: Int
    var allowsLateBlessings: Bool

    var responseWindowDuration: TimeInterval {
        TimeInterval(responseWindowMinutes * 60)
    }
}

enum ResponseWindowOptions {
    static let minutes = [1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]
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

    func occursOnCircleDay(at date: Date, timeZoneIdentifier: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.isDate(startsAt, inSameDayAs: date)
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
    let circleID: UUID
    let promptID: UUID
    let authorID: UUID
    let captureMode: CaptureMode
    let body: String?
    let audioURL: URL?
    let videoURL: URL?
    let submittedAt: Date
    let isLate: Bool
    let scriptureReference: ScriptureReference?
}

enum ResponseMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case typed
    case voice

    var id: Self { self }
    var title: String { self == .typed ? "Text" : "Voice" }
    var systemImage: String { self == .typed ? "text.cursor" : "waveform" }
}

struct BlessingResponse: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let blessingID: UUID
    let circleID: UUID
    let authorID: UUID
    let mode: ResponseMode
    let body: String
    let audioURL: URL?
    let submittedAt: Date
}

enum TimelineStatus: Hashable, Sendable {
    case blessing(Blessing)
    case missed
    case locked
    case waiting
    case joinedCircle
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
    case circleNotFound
    case notCircleOwner
    case invalidOwnerTransfer

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode: "That circle code was not found. Check it and try again."
        case .emptyBlessing: "Add a thought or record a video before sending."
        case .outsideResponseWindow: "This response window has closed."
        case .alreadySubmitted: "You already shared a blessing for this prompt."
        case .cameraUnavailable: "The camera is not available on this device."
        case .circleNotFound: "That circle is no longer available. Choose another circle."
        case .notCircleOwner: "Only the current circle owner can make that change."
        case .invalidOwnerTransfer: "Choose another current member to become the circle owner."
        }
    }
}
