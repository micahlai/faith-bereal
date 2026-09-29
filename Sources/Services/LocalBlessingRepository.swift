import Foundation

actor LocalBlessingRepository: BlessingRepository {
    private let calendar: Calendar
    private let currentUser: Member
    private var circle: Circle
    private var prompts: [DailyPrompt]
    private var blessings: [Blessing]

    init(now: Date = .now) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar

        let user = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
            displayName: "Micah",
            initials: "ML",
            tintSeed: 1
        )
        let ava = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            displayName: "Ava",
            initials: "AV",
            tintSeed: 2
        )
        let ben = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
            displayName: "Ben",
            initials: "BN",
            tintSeed: 3
        )

        currentUser = user
        circle = Circle(
            id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
            name: "Sunday Table",
            inviteCode: "LIGHT7",
            members: [user, ava, ben],
            timeZoneIdentifier: TimeZone.current.identifier
        )

        let startOfToday = calendar.startOfDay(for: now)
        let currentStart = now.addingTimeInterval(-60)
        let current = DailyPrompt(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
            circleID: circle.id,
            localDate: startOfToday,
            startsAt: currentStart,
            endsAt: currentStart.addingTimeInterval(600)
        )
        var seededPrompts = [current]
        var seededBlessings: [Blessing] = []

        for offset in 1...4 {
            let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday)!
            let promptID = UUID()
            seededPrompts.append(
                DailyPrompt(
                    id: promptID,
                    circleID: circle.id,
                    localDate: day,
                    startsAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713)),
                    endsAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713) + 600)
                )
            )
            seededBlessings.append(
                Blessing(
                    id: UUID(),
                    promptID: promptID,
                    authorID: user.id,
                    captureMode: .typed,
                    body: [
                        "A quiet walk before the rain.",
                        "A friend who called at exactly the right time.",
                        "Dinner around the same table.",
                        "Enough energy to begin again."
                    ][offset - 1],
                    videoURL: nil,
                    submittedAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713) + 123)
                )
            )
            if offset != 2 {
                seededBlessings.append(
                    Blessing(
                        id: UUID(),
                        promptID: promptID,
                        authorID: ava.id,
                        captureMode: offset == 3 ? .voice : .typed,
                        body: [
                            "Sunlight through the kitchen window.",
                            "",
                            "The patience to listen before answering.",
                            "Fresh bread and an unhurried morning."
                        ][offset - 1],
                        videoURL: nil,
                        submittedAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713) + 202)
                    )
                )
            }
        }

        prompts = seededPrompts
        blessings = seededBlessings
    }

    func bootstrap() async throws -> (Member, Circle, DailyPrompt) {
        guard let prompt = prompts.max(by: { $0.localDate < $1.localDate }) else {
            throw BlessingError.outsideResponseWindow
        }
        return (currentUser, circle, prompt)
    }

    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        let circlePrompts = prompts
            .filter { $0.circleID == circleID }
            .sorted { $0.localDate > $1.localDate }
        let currentPrompt = circlePrompts.first { calendar.isDate($0.localDate, inSameDayAs: now) }
        let viewerHasSubmitted = currentPrompt.map { prompt in
            blessings.contains { $0.promptID == prompt.id && $0.authorID == viewerID }
        } ?? false

        return circle.members.map { member in
            let events = circlePrompts.map { prompt -> TimelineEvent in
                let match = blessings.first { $0.promptID == prompt.id && $0.authorID == member.id }
                let isToday = calendar.isDate(prompt.localDate, inSameDayAs: now)
                let status: TimelineStatus

                if let match {
                    if member.id == viewerID || VisibilityPolicy.canReadPeerBlessing(
                        promptDate: prompt.localDate,
                        now: now,
                        viewerHasSubmitted: viewerHasSubmitted,
                        calendar: calendar
                    ) {
                        status = .blessing(match)
                    } else {
                        status = .locked
                    }
                } else if isToday && prompt.phase(at: now) != .closed {
                    status = .waiting
                } else {
                    status = .missed
                }
                return TimelineEvent(memberID: member.id, date: prompt.localDate, status: status)
            }
            return TimelineLane(member: member, events: events)
        }
    }

    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        videoURL: URL?,
        now: Date
    ) async throws -> Blessing {
        guard let prompt = prompts.first(where: { $0.id == promptID }), prompt.phase(at: now) == .open else {
            throw BlessingError.outsideResponseWindow
        }
        guard !blessings.contains(where: { $0.promptID == promptID && $0.authorID == authorID }) else {
            throw BlessingError.alreadySubmitted
        }
        let cleanBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .video {
            guard videoURL != nil else { throw BlessingError.emptyBlessing }
        } else {
            guard let cleanBody, !cleanBody.isEmpty else { throw BlessingError.emptyBlessing }
        }

        let blessing = Blessing(
            id: UUID(),
            promptID: promptID,
            authorID: authorID,
            captureMode: mode,
            body: cleanBody,
            videoURL: videoURL,
            submittedAt: now
        )
        blessings.append(blessing)
        return blessing
    }

    func joinCircle(code: String, memberID: UUID) async throws -> Circle {
        let normalized = code.uppercased().filter(\.isLetterOrNumber)
        guard normalized == circle.inviteCode else { throw BlessingError.invalidInviteCode }
        return circle
    }

    func createCircle(name: String, member: Member) async throws -> Circle {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw BlessingError.invalidInviteCode }
        circle = Circle(
            id: UUID(),
            name: cleaned,
            inviteCode: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased(),
            members: [member],
            timeZoneIdentifier: TimeZone.current.identifier
        )
        return circle
    }
}

