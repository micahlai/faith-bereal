import Foundation

struct BlessingWidgetSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var refreshIntervalMinutes: Int
    var prompts: [BlessingWidgetPrompt]
    var blessings: [BlessingWidgetBlessing]

    static let empty = BlessingWidgetSnapshot(
        generatedAt: .distantPast,
        refreshIntervalMinutes: 30,
        prompts: [],
        blessings: []
    )

    func content(at date: Date, recentlyShownIDs: Set<UUID> = []) -> BlessingWidgetContent {
        let activePrompts = prompts.filter { prompt in
            !prompt.viewerHasSubmitted && prompt.startsAt <= date && date < prompt.endsAt
        }
        if let prompt = activePrompts.min(by: { $0.endsAt < $1.endsAt }) {
            return .share(prompt)
        }

        let aPromptHasStartedToday = prompts.contains { $0.isOnCurrentCircleDay && $0.startsAt <= date }
        let sameDayBlessings = blessings.filter(\.isFromCurrentCircleDay)
        let eligible: [BlessingWidgetBlessing]
        if aPromptHasStartedToday, !sameDayBlessings.isEmpty {
            eligible = sameDayBlessings
        } else if !aPromptHasStartedToday {
            eligible = blessings.filter { !$0.isFromCurrentCircleDay }
        } else {
            eligible = blessings
        }

        let recentFirst = eligible.sorted { $0.submittedAt > $1.submittedAt }
        let unseen = recentFirst.filter { !recentlyShownIDs.contains($0.id) }
        let pool = unseen.isEmpty ? recentFirst : unseen
        guard !pool.isEmpty else { return .empty }

        let interval = max(1, refreshIntervalMinutes) * 60
        let rotation = Int(date.timeIntervalSince1970) / interval
        return .blessing(pool[abs(rotation) % pool.count])
    }

    func nextRefreshDate(after date: Date) -> Date {
        let intervalDate = date.addingTimeInterval(TimeInterval(max(1, refreshIntervalMinutes) * 60))
        let boundaries = prompts.flatMap { [$0.startsAt, $0.endsAt] }.filter { $0 > date }
        return min(boundaries.min() ?? intervalDate, intervalDate)
    }
}

struct BlessingWidgetPrompt: Codable, Hashable, Sendable {
    let promptID: UUID
    let circleID: UUID
    let circleName: String
    let startsAt: Date
    let endsAt: Date
    let viewerHasSubmitted: Bool
    let isOnCurrentCircleDay: Bool

    var deepLink: URL? {
        URL(string: "blessingcircle://today?circle=\(circleID.uuidString)")
    }
}

struct BlessingWidgetBlessing: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let circleID: UUID
    let circleName: String
    let authorName: String
    let captureMode: BlessingWidgetCaptureMode
    let transcript: String
    let submittedAt: Date
    let isFromCurrentCircleDay: Bool
    let scriptureReference: String?
    var scriptureText: String?
    let bibleVersionName: String?

    var deepLink: URL? {
        URL(string: "blessingcircle://blessing/\(id.uuidString)?circle=\(circleID.uuidString)")
    }
}

enum BlessingWidgetCaptureMode: String, Codable, Hashable, Sendable {
    case typed
    case voice
    case video
}

enum BlessingWidgetContent: Hashable, Sendable {
    case share(BlessingWidgetPrompt)
    case blessing(BlessingWidgetBlessing)
    case empty

    var deepLink: URL? {
        switch self {
        case let .share(prompt): prompt.deepLink
        case let .blessing(blessing): blessing.deepLink
        case .empty: URL(string: "blessingcircle://today")
        }
    }
}

enum BlessingWidgetSnapshotStore {
    static let appGroupIdentifier = "group.app.blessingcircle.shared"
    private static let snapshotKey = "widget.snapshot.v1"
    private static let recentlyShownKey = "widget.recentlyShown.v1"
    private static let snapshotFileName = "widget-snapshot-v1.json"

    static func save(_ snapshot: BlessingWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let snapshotURL {
            try? data.write(to: snapshotURL, options: .atomic)
        }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> BlessingWidgetSnapshot {
        let data = snapshotURL.flatMap { try? Data(contentsOf: $0) }
            ?? defaults.data(forKey: snapshotKey)
        guard let data,
              let snapshot = try? JSONDecoder().decode(BlessingWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func recentlyShownIDs() -> Set<UUID> {
        Set((defaults.stringArray(forKey: recentlyShownKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func markShown(_ blessingID: UUID) {
        var values = defaults.stringArray(forKey: recentlyShownKey) ?? []
        values.removeAll { $0 == blessingID.uuidString }
        values.append(blessingID.uuidString)
        defaults.set(Array(values.suffix(40)), forKey: recentlyShownKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(snapshotFileName, isDirectory: false)
    }
}
