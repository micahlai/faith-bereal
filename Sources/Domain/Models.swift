import Foundation

enum FirstDaySubmissionPolicy {
    static func isEligible(memberJoinedAt: Date, prompt: DailyPrompt, circle: CircleGroup, now: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: circle.timeZoneIdentifier) ?? .current
        return calendar.isDate(memberJoinedAt, inSameDayAs: prompt.startsAt)
            && calendar.isDate(now, inSameDayAs: prompt.startsAt)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

enum AppIconPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case cream
    case midnight

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .cream: "Cream"
        case .midnight: "Midnight"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "circle.lefthalf.filled"
        case .cream: "sun.max.fill"
        case .midnight: "moon.stars.fill"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .automatic: nil
        case .cream: "MannaLight"
        case .midnight: "MannaDark"
        }
    }

    init(alternateIconName: String?) {
        switch alternateIconName {
        case "MannaLight": self = .cream
        case "MannaDark": self = .midnight
        default: self = .automatic
        }
    }
}

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
    var avatarURL: URL? = nil
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
    var repeatWindowMinutes: Int
    var photoURL: URL? = nil
    var circleActivityNotificationsEnabled: Bool = true

    var responseWindowDuration: TimeInterval {
        TimeInterval(responseWindowMinutes * 60)
    }

    func preservingInviteCode(_ knownCode: String?) -> CircleGroup {
        guard inviteCode.isEmpty,
              let knownCode,
              !knownCode.isEmpty else { return self }
        var resolved = self
        resolved.inviteCode = knownCode
        return resolved
    }
}

enum ResponseWindowOptions {
    static let minutes = [1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180]
}

enum RepeatWindowOptions {
    static let minutes = [15, 30, 60, 90, 120, 180, 360, 720, 1_440]
}

struct CircleConfiguration: Equatable, Sendable {
    var name: String
    var timeZoneIdentifier: String
    var randomWindowStartMinutes: Int
    var randomWindowEndMinutes: Int
    var responseWindowMinutes: Int
    var allowsLateBlessings: Bool
    var repeatWindowMinutes: Int

    static func defaults(timeZoneIdentifier: String = TimeZone.current.identifier) -> CircleConfiguration {
        CircleConfiguration(
            name: "",
            timeZoneIdentifier: timeZoneIdentifier,
            randomWindowStartMinutes: 12 * 60,
            randomWindowEndMinutes: 22 * 60,
            responseWindowMinutes: 10,
            allowsLateBlessings: true,
            repeatWindowMinutes: 120
        )
    }

    var isValid: Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanedName.isEmpty
            && cleanedName.count <= 80
            && TimeZone(identifier: timeZoneIdentifier) != nil
            && (0..<1_440).contains(randomWindowStartMinutes)
            && (1...1_440).contains(randomWindowEndMinutes)
            && randomWindowEndMinutes > randomWindowStartMinutes
            && ResponseWindowOptions.minutes.contains(responseWindowMinutes)
            && RepeatWindowOptions.minutes.contains(repeatWindowMinutes)
    }
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

struct CirclePromptDispatch: Equatable, Sendable {
    let prompt: DailyPrompt
    let deliveredNotifications: Int
    let attemptedNotifications: Int
    let registeredDevices: Int
    let memberCount: Int
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
    var repeatedFromBlessingID: UUID? = nil
    var photoURL: URL? = nil
    var editedAt: Date? = nil
}

enum BlessingEditPolicy {
    static let window: TimeInterval = 10 * 60

    static func canEdit(_ blessing: Blessing, authorID: UUID, at date: Date) -> Bool {
        blessing.authorID == authorID
            && date >= blessing.submittedAt
            && date < blessing.submittedAt.addingTimeInterval(window)
    }
}

struct BlessingFeedItem: Identifiable, Hashable, Sendable {
    let member: Member
    let blessing: Blessing

    var id: UUID { blessing.id }
}

enum RepeatBlessingPolicy {
    static func isEligible(
        source: Blessing,
        targetCircle: CircleGroup,
        authorID: UUID,
        now: Date
    ) -> Bool {
        guard source.authorID == authorID,
              source.circleID != targetCircle.id,
              source.submittedAt <= now else { return false }
        return now.timeIntervalSince(source.submittedAt)
            <= TimeInterval(targetCircle.repeatWindowMinutes * 60)
    }
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

enum ResponseCompositionPolicy {
    static func canRespond(to blessing: Blessing, currentPrompt: DailyPrompt?, isCurrentPromptToday: Bool) -> Bool {
        guard let currentPrompt, isCurrentPromptToday else { return false }
        return blessing.promptID == currentPrompt.id
    }
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
    case invalidMemberRemoval
    case profileSaveTimedOut
    case blessingEditWindowClosed
    case notBlessingAuthor

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
        case .invalidMemberRemoval: "Choose another current member to remove from the circle."
        case .profileSaveTimedOut: "The profile photo upload timed out. Check your connection and try again."
        case .blessingEditWindowClosed: "Blessings can only be edited for 10 minutes after sharing."
        case .notBlessingAuthor: "You can only edit your own blessing."
        }
    }
}
