import Foundation

private struct BlessingEntryGrantKey: Hashable, Sendable {
    let promptID: UUID
    let memberID: UUID
}

actor LocalBlessingRepository: BlessingRepository {
    private let calendar: Calendar
    private var currentUser: Member
    private var circles: [CircleGroup]
    private var prompts: [DailyPrompt]
    private var blessings: [Blessing]
    private var blessingResponses: [BlessingResponse]
    private var entryGrants: Set<BlessingEntryGrantKey> = []

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
        let primaryCircle = CircleGroup(
            id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
            name: "Sunday Table",
            inviteCode: "LIGHT7",
            ownerID: user.id,
            members: [user, ava, ben],
            timeZoneIdentifier: TimeZone.current.identifier,
            randomWindowStartMinutes: 8 * 60,
            randomWindowEndMinutes: 20 * 60,
            responseWindowMinutes: 10,
            allowsLateBlessings: true,
            repeatWindowMinutes: 120
        )

        let currentStart = now.addingTimeInterval(-60)
        let current = DailyPrompt(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
            circleID: primaryCircle.id,
            localDate: startOfToday,
            startsAt: currentStart,
            endsAt: currentStart.addingTimeInterval(600)
        )
        var seededPrompts = [current]
        var seededBlessings: [Blessing] = [
            Blessing(
                id: UUID(),
                circleID: primaryCircle.id,
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
                    circleID: primaryCircle.id,
                    localDate: day,
                    startsAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713)),
                    endsAt: day.addingTimeInterval(12 * 3600 + Double(offset * 713) + 600)
                )
            )
            seededBlessings.append(
                Blessing(
                    id: UUID(),
                    circleID: primaryCircle.id,
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
                        circleID: primaryCircle.id,
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

        let grace = Member(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!,
            displayName: "Grace",
            initials: "GR",
            tintSeed: 4,
            joinedAt: calendar.date(byAdding: .day, value: -6, to: startOfToday)!
        )
        let prayerCircle = CircleGroup(
            id: UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!,
            name: "Morning Prayer",
            inviteCode: "GRACE8",
            ownerID: grace.id,
            members: [
                Member(
                    id: user.id,
                    displayName: user.displayName,
                    initials: user.initials,
                    tintSeed: user.tintSeed,
                    bibleVersionID: user.bibleVersionID,
                    joinedAt: calendar.date(byAdding: .day, value: -5, to: startOfToday)!
                ),
                grace,
            ],
            timeZoneIdentifier: TimeZone.current.identifier,
            randomWindowStartMinutes: 6 * 60,
            randomWindowEndMinutes: 10 * 60,
            responseWindowMinutes: 15,
            allowsLateBlessings: false,
            repeatWindowMinutes: 90
        )
        let prayerStart = now.addingTimeInterval(-120)
        seededPrompts.append(
            DailyPrompt(
                id: UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!,
                circleID: prayerCircle.id,
                localDate: startOfToday,
                startsAt: prayerStart,
                endsAt: prayerStart.addingTimeInterval(900)
            )
        )

        circles = [primaryCircle, prayerCircle]
        prompts = seededPrompts
        blessings = seededBlessings
        blessingResponses = []
    }

    func bootstrap() async throws -> AppBootstrap {
        let memberCircles = circles.filter { circle in
            circle.members.contains(where: { $0.id == currentUser.id })
        }
        let selectedCircleID = memberCircles.first?.id
        let prompt = selectedCircleID.flatMap { id in
            prompts.filter { $0.circleID == id }.max(by: { $0.localDate < $1.localDate })
        }
        return AppBootstrap(
            currentUser: currentUser,
            circles: memberCircles,
            selectedCircleID: selectedCircleID,
            prompt: prompt
        )
    }

    func circleContext(circleID: UUID) async throws -> CircleContext {
        guard let circle = circles.first(where: {
            $0.id == circleID && $0.members.contains(where: { $0.id == currentUser.id })
        }) else {
            throw BlessingError.circleNotFound
        }
        let prompt = prompts
            .filter { $0.circleID == circleID }
            .max(by: { $0.localDate < $1.localDate })
        return CircleContext(circle: circle, prompt: prompt)
    }

    func timelineUpdates(circleID: UUID) async throws -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func registerDevice(
        installationID: UUID,
        apnsToken: String?,
        pushToStartToken: String?,
        environment: String
    ) async throws {}

    func registerActivity(
        promptID: UUID,
        activityID: String,
        pushToken: String,
        environment: String
    ) async throws {}

    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        guard let circle = circles.first(where: { $0.id == circleID }) else {
            throw BlessingError.circleNotFound
        }
        let circlePrompts = prompts
            .filter { $0.circleID == circleID }
            .sorted { $0.localDate > $1.localDate }
        let currentPrompt = circlePrompts.first { calendar.isDate($0.localDate, inSameDayAs: now) }
        let viewerHasSubmitted = currentPrompt.map { prompt in
            blessings.contains { $0.promptID == prompt.id && $0.authorID == viewerID }
        } ?? false

        return circle.members.map { member in
            var events = circlePrompts
                .filter {
                    $0.startsAt >= member.joinedAt
                        || calendar.isDate($0.startsAt, inSameDayAs: member.joinedAt)
                }
                .map { prompt -> TimelineEvent in
                let match = blessings.first { $0.promptID == prompt.id && $0.authorID == member.id }
                let isToday = calendar.isDate(prompt.localDate, inSameDayAs: now)
                let status: TimelineStatus

                if isToday && member.id != viewerID && !viewerHasSubmitted {
                    status = .locked
                } else if let match {
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
                } else if isToday && (prompt.phase(at: now) != .closed || circle.allowsLateBlessings || FirstDaySubmissionPolicy.isEligible(memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle, now: now)) {
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

    func beginBlessingEntry(promptID: UUID, memberID: UUID, now: Date) async throws {
        guard let prompt = prompts.first(where: { $0.id == promptID }),
              let circle = circles.first(where: { $0.id == prompt.circleID }) else {
            throw BlessingError.outsideResponseWindow
        }
        guard !blessings.contains(where: { $0.promptID == promptID && $0.authorID == memberID }) else {
            throw BlessingError.alreadySubmitted
        }
        guard acceptsEntry(prompt: prompt, circle: circle, memberID: memberID, now: now) else {
            throw BlessingError.outsideResponseWindow
        }
        entryGrants.insert(BlessingEntryGrantKey(promptID: promptID, memberID: memberID))
    }

    func submit(
        promptID: UUID,
        authorID: UUID,
        mode: CaptureMode,
        body: String?,
        audioURL: URL?,
        videoURL: URL?,
        photoURL: URL? = nil,
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
        guard let circle = circles.first(where: { $0.id == prompt.circleID }) else {
            throw BlessingError.circleNotFound
        }
        let hasEntryGrant = entryGrants.contains(
            BlessingEntryGrantKey(promptID: promptID, memberID: authorID)
        )
        guard hasEntryGrant || acceptsEntry(
            prompt: prompt,
            circle: circle,
            memberID: authorID,
            now: now,
            nextPromptStart: nextPromptStart
        ) else { throw BlessingError.outsideResponseWindow }
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
            guard videoURL != nil, photoURL == nil else { throw BlessingError.emptyBlessing }
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
            scriptureReference: scriptureReference,
            photoURL: photoURL
        )
        blessings.append(blessing)
        return blessing
    }

    private func acceptsEntry(
        prompt: DailyPrompt,
        circle: CircleGroup,
        memberID: UUID,
        now: Date,
        nextPromptStart: Date? = nil
    ) -> Bool {
        let resolvedNextPromptStart = nextPromptStart ?? prompts
            .filter { $0.circleID == prompt.circleID && $0.startsAt > prompt.startsAt }
            .map(\.startsAt)
            .min()
        let joinedAt = circle.members.first(where: { $0.id == memberID })?.joinedAt
        guard joinedAt != nil else { return false }
        let isFirstDay = joinedAt.map {
            FirstDaySubmissionPolicy.isEligible(
                memberJoinedAt: $0,
                prompt: prompt,
                circle: circle,
                now: now
            )
        } ?? false
        let isAcceptedLate = circle.allowsLateBlessings
            && now >= prompt.endsAt
            && resolvedNextPromptStart.map { now < $0 } ?? true
        return prompt.phase(at: now) == .open || isAcceptedLate || isFirstDay
    }

    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let index = circles.firstIndex(where: { $0.inviteCode == normalized }) else {
            throw BlessingError.invalidInviteCode
        }
        if !circles[index].members.contains(where: { $0.id == memberID }) {
            var member = currentUser
            member.joinedAt = .now
            circles[index].members.append(member)
        }
        return circles[index]
    }

    func createCircle(configuration: CircleConfiguration, member: Member) async throws -> CircleGroup {
        guard configuration.isValid else { throw BlessingError.invalidInviteCode }
        let now = Date.now
        var owner = member
        owner.joinedAt = now
        let circle = CircleGroup(
            id: UUID(),
            name: configuration.name.trimmingCharacters(in: .whitespacesAndNewlines),
            inviteCode: uniqueInviteCode(),
            ownerID: member.id,
            members: [owner],
            timeZoneIdentifier: configuration.timeZoneIdentifier,
            randomWindowStartMinutes: configuration.randomWindowStartMinutes,
            randomWindowEndMinutes: configuration.randomWindowEndMinutes,
            responseWindowMinutes: configuration.responseWindowMinutes,
            allowsLateBlessings: configuration.allowsLateBlessings,
            repeatWindowMinutes: configuration.repeatWindowMinutes
        )
        circles.append(circle)

        var circleCalendar = Calendar(identifier: .gregorian)
        circleCalendar.timeZone = TimeZone(identifier: configuration.timeZoneIdentifier) ?? .current
        let localDate = circleCalendar.startOfDay(for: now)
        let configuredStart = circleCalendar.date(
            byAdding: .minute,
            value: configuration.randomWindowStartMinutes,
            to: localDate
        ) ?? localDate
        let configuredEnd = circleCalendar.date(
            byAdding: .minute,
            value: configuration.randomWindowEndMinutes,
            to: localDate
        ) ?? configuredStart
        let availableStart = now < configuredEnd ? max(configuredStart, now) : configuredStart
        let availableDuration = max(0, configuredEnd.timeIntervalSince(availableStart))
        let randomOffset = availableDuration > 1 ? Double.random(in: 0..<availableDuration) : 0
        let promptStart = availableStart.addingTimeInterval(randomOffset)
        prompts.append(
            DailyPrompt(
                id: UUID(),
                circleID: circle.id,
                localDate: localDate,
                startsAt: promptStart,
                endsAt: promptStart.addingTimeInterval(circle.responseWindowDuration)
            )
        )
        return circle
    }

    func regenerateInviteCode(circleID: UUID, ownerID: UUID) async throws -> CircleGroup {
        guard let index = circles.firstIndex(where: { $0.id == circleID }) else {
            throw BlessingError.circleNotFound
        }
        guard circles[index].ownerID == ownerID else { throw BlessingError.notCircleOwner }
        circles[index].inviteCode = uniqueInviteCode()
        return circles[index]
    }

    func updateCircleSettings(
        circleID: UUID,
        ownerID: UUID,
        name: String,
        timeZoneIdentifier: String,
        randomWindowStartMinutes: Int,
        randomWindowEndMinutes: Int,
        responseWindowMinutes: Int,
        allowsLateBlessings: Bool,
        repeatWindowMinutes: Int
    ) async throws -> CircleGroup {
        guard let index = circles.firstIndex(where: { $0.id == circleID }),
              circles[index].ownerID == ownerID else {
            throw BlessingError.invalidInviteCode
        }
        guard ResponseWindowOptions.minutes.contains(responseWindowMinutes) else {
            throw BlessingError.outsideResponseWindow
        }
        guard RepeatWindowOptions.minutes.contains(repeatWindowMinutes) else {
            throw BlessingError.invalidInviteCode
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
        circles[index].name = cleanedName
        circles[index].timeZoneIdentifier = timeZoneIdentifier
        circles[index].randomWindowStartMinutes = randomWindowStartMinutes
        circles[index].randomWindowEndMinutes = randomWindowEndMinutes
        circles[index].responseWindowMinutes = responseWindowMinutes
        circles[index].allowsLateBlessings = allowsLateBlessings
        circles[index].repeatWindowMinutes = repeatWindowMinutes
        return circles[index]
    }

    private func uniqueInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var code: String
        repeat {
            code = String((0..<6).compactMap { _ in alphabet.randomElement() })
        } while circles.contains(where: { $0.inviteCode == code })
        return code
    }

    func forceCirclePrompt(
        circleID: UUID,
        ownerID: UUID,
        now: Date
    ) async throws -> CirclePromptDispatch {
        guard let circle = circles.first(where: { $0.id == circleID }) else {
            throw BlessingError.circleNotFound
        }
        guard circle.ownerID == ownerID else {
            throw BlessingError.notCircleOwner
        }

        let forcedPrompt = try beginLocalPrompt(circle: circle, now: now)
        return CirclePromptDispatch(
            prompt: forcedPrompt,
            deliveredNotifications: 0,
            attemptedNotifications: 0,
            registeredDevices: 0,
            memberCount: circle.members.count
        )
    }

    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member {
        guard currentUser.id == memberID,
              BibleTranslation.publicDomain.contains(where: { $0.id == versionID }) else {
            throw BlessingError.invalidInviteCode
        }
        currentUser.bibleVersionID = versionID
        for circleIndex in circles.indices {
            if let memberIndex = circles[circleIndex].members.firstIndex(where: { $0.id == memberID }) {
                circles[circleIndex].members[memberIndex].bibleVersionID = versionID
            }
        }
        return currentUser
    }

    func updateProfile(memberID: UUID, displayName: String, avatarURL: URL?) async throws -> Member {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentUser.id == memberID, !cleaned.isEmpty, cleaned.count <= 60 else {
            throw BlessingError.invalidInviteCode
        }
        currentUser.displayName = cleaned
        currentUser.initials = Self.initials(for: cleaned)
        currentUser.avatarURL = avatarURL
        for circleIndex in circles.indices {
            if let memberIndex = circles[circleIndex].members.firstIndex(where: { $0.id == memberID }) {
                circles[circleIndex].members[memberIndex].displayName = cleaned
                circles[circleIndex].members[memberIndex].initials = currentUser.initials
                circles[circleIndex].members[memberIndex].avatarURL = avatarURL
            }
        }
        return currentUser
    }

    private static func initials(for name: String) -> String {
        let value = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return value.isEmpty ? "MC" : value
    }

    func transferCircleOwnership(
        circleID: UUID,
        ownerID: UUID,
        newOwnerID: UUID
    ) async throws -> CircleGroup {
        guard let circleIndex = circles.firstIndex(where: { $0.id == circleID }) else {
            throw BlessingError.circleNotFound
        }
        guard circles[circleIndex].ownerID == ownerID else {
            throw BlessingError.notCircleOwner
        }
        guard newOwnerID != ownerID,
              circles[circleIndex].members.contains(where: { $0.id == newOwnerID }) else {
            throw BlessingError.invalidOwnerTransfer
        }
        circles[circleIndex].ownerID = newOwnerID
        return circles[circleIndex]
    }

    func removeCircleMember(circleID: UUID, ownerID: UUID, memberID: UUID) async throws -> CircleGroup {
        guard let circleIndex = circles.firstIndex(where: { $0.id == circleID }) else {
            throw BlessingError.circleNotFound
        }
        guard circles[circleIndex].ownerID == ownerID else {
            throw BlessingError.notCircleOwner
        }
        guard memberID != ownerID,
              let memberIndex = circles[circleIndex].members.firstIndex(where: { $0.id == memberID }) else {
            throw BlessingError.invalidMemberRemoval
        }
        circles[circleIndex].members.remove(at: memberIndex)
        return circles[circleIndex]
    }

    func recentBlessings(authorID: UUID, submittedAfter: Date) async throws -> [Blessing] {
        blessings
            .filter { $0.authorID == authorID && $0.submittedAt >= submittedAfter }
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    func repeatBlessing(
        sourceBlessingID: UUID,
        targetPromptID: UUID,
        authorID: UUID,
        now: Date
    ) async throws -> Blessing {
        guard let source = blessings.first(where: { $0.id == sourceBlessingID }),
              let targetPrompt = prompts.first(where: { $0.id == targetPromptID }),
              let targetCircle = circles.first(where: { $0.id == targetPrompt.circleID }) else {
            throw BlessingError.circleNotFound
        }
        guard RepeatBlessingPolicy.isEligible(
            source: source,
            targetCircle: targetCircle,
            authorID: authorID,
            now: now
        ) else {
            throw BlessingError.outsideResponseWindow
        }

        var repeated = try await submit(
            promptID: targetPromptID,
            authorID: authorID,
            mode: .typed,
            body: source.body,
            audioURL: nil,
            videoURL: nil,
            photoURL: nil,
            scriptureReference: source.scriptureReference,
            now: now
        )
        repeated.repeatedFromBlessingID = source.id
        if let index = blessings.firstIndex(where: { $0.id == repeated.id }) {
            blessings[index] = repeated
        }
        return repeated
    }

    func leaveCircle(circleID: UUID, memberID: UUID) async throws {
        guard let circleIndex = circles.firstIndex(where: { $0.id == circleID }),
              let memberIndex = circles[circleIndex].members.firstIndex(where: { $0.id == memberID }) else {
            throw BlessingError.circleNotFound
        }
        let wasOwner = circles[circleIndex].ownerID == memberID
        circles[circleIndex].members.remove(at: memberIndex)
        if circles[circleIndex].members.isEmpty {
            circles.remove(at: circleIndex)
        } else if wasOwner,
                  let successor = circles[circleIndex].members.min(by: { $0.joinedAt < $1.joinedAt }) {
            circles[circleIndex].ownerID = successor.id
        }
    }

    func responses(blessingID: UUID, viewerID: UUID) async throws -> [BlessingResponse] {
        guard let blessing = blessings.first(where: { $0.id == blessingID }),
              let circle = circles.first(where: { $0.id == blessing.circleID }),
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
              let circle = circles.first(where: { $0.id == circleID }),
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

#if DEBUG
extension LocalBlessingRepository: DebugPromptProviding {
    func beginDebugPrompt(circleID: UUID, now: Date) async throws -> DailyPrompt {
        guard let circle = circles.first(where: {
            $0.id == circleID && $0.members.contains(where: { $0.id == currentUser.id })
        }) else {
            throw BlessingError.circleNotFound
        }

        return try beginLocalPrompt(circle: circle, now: now)
    }
}
#endif

private extension LocalBlessingRepository {
    func beginLocalPrompt(circle: CircleGroup, now: Date) throws -> DailyPrompt {
        var circleCalendar = Calendar(identifier: .gregorian)
        circleCalendar.timeZone = TimeZone(identifier: circle.timeZoneIdentifier) ?? .current
        let localDate = circleCalendar.startOfDay(for: now)
        let existingIndex = prompts.firstIndex {
            $0.circleID == circle.id && circleCalendar.isDate($0.localDate, inSameDayAs: now)
        }
        let promptID = existingIndex.map { prompts[$0].id } ?? UUID()
        let debugPrompt = DailyPrompt(
            id: promptID,
            circleID: circle.id,
            localDate: localDate,
            startsAt: now,
            endsAt: now.addingTimeInterval(circle.responseWindowDuration)
        )

        let resetBlessingIDs = Set(
            blessings
                .filter { $0.promptID == promptID && $0.authorID == currentUser.id }
                .map(\.id)
        )
        blessings.removeAll { resetBlessingIDs.contains($0.id) }
        blessingResponses.removeAll { resetBlessingIDs.contains($0.blessingID) }

        if let existingIndex {
            prompts[existingIndex] = debugPrompt
        } else {
            prompts.append(debugPrompt)
        }
        return debugPrompt
    }
}
