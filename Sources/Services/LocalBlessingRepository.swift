import Foundation

actor LocalBlessingRepository: BlessingRepository {
    private let calendar: Calendar
    private var currentUser: Member
    private var circle: CircleGroup
    private var prompts: [DailyPrompt]
    private var blessings: [Blessing]
    private var blessingResponses: [BlessingResponse]

    init(now: Date = .now) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
        let startOfToday = calendar.startOfDay(for: now)

        let user = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
            displayName: "Micah",
            initials: "ML",
            tintSeed: 1,
            joinedAt: calendar.date(byAdding: .day, value: -14, to: startOfToday)!
        )
        let ava = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            displayName: "Ava",
            initials: "AV",
            tintSeed: 2,
            joinedAt: calendar.date(byAdding: .day, value: -3, to: startOfToday)!.addingTimeInterval(9 * 3_600)
        )
        let ben = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
            displayName: "Ben",
            initials: "BN",
            tintSeed: 3,
            joinedAt: calendar.date(byAdding: .day, value: -1, to: startOfToday)!.addingTimeInterval(8 * 3_600)
        )

        currentUser = user
        circle = CircleGroup(
            id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
            name: "Sunday Table",
            inviteCode: "LIGHT7",
            ownerID: user.id,
            members: [user, ava, ben],
            timeZoneIdentifier: TimeZone.current.identifier,
            randomWindowStartMinutes: 8 * 60,
            randomWindowEndMinutes: 20 * 60,
            responseWindowMinutes: 10,
            allowsLateBlessings: true
        )

        let currentStart = now.addingTimeInterval(-60)
        let current = DailyPrompt(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
            circleID: circle.id,
            localDate: startOfToday,
            startsAt: currentStart,
            endsAt: currentStart.addingTimeInterval(600)
        )
        var seededPrompts = [current]
        var seededBlessings: [Blessing] = [
            Blessing(
                id: UUID(),
                circleID: circle.id,
                promptID: current.id,
                authorID: ava.id,
                captureMode: .voice,
                body: "A hard conversation that ended with more understanding.",
                audioURL: nil,
                videoURL: nil,
                submittedAt: currentStart.addingTimeInterval(82),
                isLate: false,
                scriptureReference: ScriptureReference(
                    bookSlug: "philippians",
                    bookName: "Philippians",
                    chapter: 4,
                    verseStart: 6,
                    verseEnd: 7
                )
            )
        ]

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
                    circleID: circle.id,
                    promptID: promptID,
                    authorID: user.id,
                    captureMode: .typed,
                    body: [
                        "A quiet walk before the rain.",
                        "A friend who called at exactly the right time.",
                        "Dinner around the same table.",
                        "Enough energy to begin again."
                    ][offset - 1],
                    audioURL: nil,
                    videoURL: nil,
                    submittedAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713) + 123),
                    isLate: false,
                    scriptureReference: offset == 1
                        ? ScriptureReference(
                            bookSlug: "psalms",
                            bookName: "Psalms",
                            chapter: 118,
                            verseStart: 24,
                            verseEnd: 24
                        )
                        : nil
                )
            )
            if offset != 2 {
                seededBlessings.append(
                    Blessing(
                        id: UUID(),
                        circleID: circle.id,
                        promptID: promptID,
                        authorID: ava.id,
                        captureMode: offset == 3 ? .voice : .typed,
                        body: [
                            "Sunlight through the kitchen window.",
                            "",
                            "The patience to listen before answering.",
                            "Fresh bread and an unhurried morning."
                        ][offset - 1],
                        audioURL: nil,
                        videoURL: nil,
                        submittedAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713) + (offset == 3 ? 702 : 202)),
                        isLate: offset == 3,
                        scriptureReference: nil
                    )
                )
            }
        }

        prompts = seededPrompts
        blessings = seededBlessings
        blessingResponses = []
    }

    func bootstrap() async throws -> AppBootstrap {
        guard let prompt = prompts.max(by: { $0.localDate < $1.localDate }) else {
            throw BlessingError.outsideResponseWindow
        }
        return AppBootstrap(currentUser: currentUser, circle: circle, prompt: prompt)
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
            var events = circlePrompts
                .filter { $0.startsAt >= member.joinedAt }
                .map { prompt -> TimelineEvent in
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
                } else if isToday && (prompt.phase(at: now) != .closed || circle.allowsLateBlessings) {
                    status = .waiting
                } else {
                    status = .missed
                }
                return TimelineEvent(memberID: member.id, date: prompt.localDate, status: status)
            }
            events.append(
                TimelineEvent(memberID: member.id, date: member.joinedAt, status: .joinedCircle)
            )
            return TimelineLane(member: member, events: events)
        }
    }

    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        audioURL: URL?,
        videoURL: URL?,
        scriptureReference: ScriptureReference?,
        now: Date
    ) async throws -> Blessing {
        guard let prompt = prompts.first(where: { $0.id == promptID }) else {
            throw BlessingError.outsideResponseWindow
        }
        let nextPromptStart = prompts
            .filter { $0.circleID == prompt.circleID && $0.startsAt > prompt.startsAt }
            .map(\.startsAt)
            .min()
        let isWithinWindow = prompt.phase(at: now) == .open
        let isAcceptedLate = circle.allowsLateBlessings
            && now >= prompt.endsAt
            && nextPromptStart.map { now < $0 } ?? true
        guard isWithinWindow || isAcceptedLate else { throw BlessingError.outsideResponseWindow }
        guard !blessings.contains(where: { $0.promptID == promptID && $0.authorID == authorID }) else {
            throw BlessingError.alreadySubmitted
        }
        let cleanBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleanBody, !cleanBody.isEmpty else { throw BlessingError.emptyBlessing }
        switch mode {
        case .typed:
            break
        case .voice:
            guard audioURL != nil else { throw BlessingError.emptyBlessing }
        case .video:
            guard videoURL != nil else { throw BlessingError.emptyBlessing }
        }

        let blessing = Blessing(
            id: UUID(),
            circleID: prompt.circleID,
            promptID: promptID,
            authorID: authorID,
            captureMode: mode,
            body: cleanBody,
            audioURL: audioURL,
            videoURL: videoURL,
            submittedAt: now,
            isLate: now >= prompt.endsAt,
            scriptureReference: scriptureReference
        )
        blessings.append(blessing)
        return blessing
    }

    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized == circle.inviteCode else { throw BlessingError.invalidInviteCode }
        return circle
    }

    func createCircle(name: String, member: Member) async throws -> CircleGroup {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw BlessingError.invalidInviteCode }
        circle = CircleGroup(
            id: UUID(),
            name: cleaned,
            inviteCode: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased(),
            ownerID: member.id,
            members: [member],
            timeZoneIdentifier: TimeZone.current.identifier,
            randomWindowStartMinutes: 8 * 60,
            randomWindowEndMinutes: 20 * 60,
            responseWindowMinutes: 10,
            allowsLateBlessings: false
        )
        return circle
    }

    func updateCircleSettings(
        circleID: UUID,
        ownerID: UUID,
        name: String,
        timeZoneIdentifier: String,
        randomWindowStartMinutes: Int,
        randomWindowEndMinutes: Int,
        responseWindowMinutes: Int,
        allowsLateBlessings: Bool
    ) async throws -> CircleGroup {
        guard circle.id == circleID, circle.ownerID == ownerID else {
            throw BlessingError.invalidInviteCode
        }
        guard ResponseWindowOptions.minutes.contains(responseWindowMinutes) else {
            throw BlessingError.outsideResponseWindow
        }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              cleanedName.count <= 80,
              TimeZone(identifier: timeZoneIdentifier) != nil,
              (0..<1_440).contains(randomWindowStartMinutes),
              (1...1_440).contains(randomWindowEndMinutes),
              randomWindowEndMinutes > randomWindowStartMinutes else {
            throw BlessingError.invalidInviteCode
        }
        circle.name = cleanedName
        circle.timeZoneIdentifier = timeZoneIdentifier
        circle.randomWindowStartMinutes = randomWindowStartMinutes
        circle.randomWindowEndMinutes = randomWindowEndMinutes
        circle.responseWindowMinutes = responseWindowMinutes
        circle.allowsLateBlessings = allowsLateBlessings
        return circle
    }

    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member {
        guard currentUser.id == memberID,
              BibleTranslation.publicDomain.contains(where: { $0.id == versionID }) else {
            throw BlessingError.invalidInviteCode
        }
        currentUser.bibleVersionID = versionID
        if let index = circle.members.firstIndex(where: { $0.id == memberID }) {
            circle.members[index].bibleVersionID = versionID
        }
        return currentUser
    }

    func responses(blessingID: UUID, viewerID: UUID) async throws -> [BlessingResponse] {
        guard let blessing = blessings.first(where: { $0.id == blessingID }),
              circle.id == blessing.circleID,
              circle.members.contains(where: { $0.id == viewerID }) else {
            throw BlessingError.invalidInviteCode
        }
        return blessingResponses
            .filter { $0.blessingID == blessingID && $0.circleID == blessing.circleID }
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    func submitResponse(
        blessingID: UUID,
        circleID: UUID,
        authorID: UUID,
        mode: ResponseMode,
        body: String,
        audioURL: URL?,
        now: Date
    ) async throws -> BlessingResponse {
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let blessing = blessings.first(where: { $0.id == blessingID }),
              blessing.circleID == circleID,
              circle.id == circleID,
              circle.members.contains(where: { $0.id == authorID }),
              !cleanedBody.isEmpty else {
            throw BlessingError.emptyBlessing
        }
        if mode == .voice, audioURL == nil { throw BlessingError.emptyBlessing }
        if mode == .typed, audioURL != nil { throw BlessingError.emptyBlessing }

        let response = BlessingResponse(
            id: UUID(),
            blessingID: blessingID,
            circleID: circleID,
            authorID: authorID,
            mode: mode,
            body: cleanedBody,
            audioURL: audioURL,
            submittedAt: now
        )
        blessingResponses.append(response)
        return response
    }
}
