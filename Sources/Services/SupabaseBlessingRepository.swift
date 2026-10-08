import Foundation
import Supabase

actor SupabaseBlessingRepository: BlessingRepository {
    private let client: SupabaseClient
    private let mediaBucket = "blessing-media"
    private let avatarBucket = "avatars"
    private let circlePhotoBucket = "circle-photos"

    init(client: SupabaseClient) {
        self.client = client
    }

    func bootstrap() async throws -> AppBootstrap {
        let userID = try await client.auth.session.user.id
        let profile = try await fetchProfile(userID: userID)
        let currentUser = try await member(from: profile, joinedAt: .distantPast)

        let memberships: [MembershipRow] = try await client
            .from("circle_members")
            .select()
            .eq("user_id", value: userID)
            .is("removed_at", value: nil)
            .order("joined_at", ascending: false)
            .execute()
            .value
        guard let selectedMembership = memberships.first else {
            return AppBootstrap(
                currentUser: currentUser,
                circles: [],
                selectedCircleID: nil,
                prompt: nil
            )
        }

        var circles: [CircleGroup] = []
        for membership in memberships {
            circles.append(try await fetchCircle(id: membership.circleID, inviteCode: ""))
        }
        let selectedCircle = circles.first(where: { $0.id == selectedMembership.circleID })
        let currentPrompt: DailyPrompt?
        let endOfDayPrompt: DailyPrompt?
        if let selectedCircle {
            let prompts = try await fetchCurrentPrompts(circle: selectedCircle)
            currentPrompt = prompts.daily
            endOfDayPrompt = prompts.endOfDay
        } else {
            currentPrompt = nil
            endOfDayPrompt = nil
        }
        return AppBootstrap(
            currentUser: currentUser,
            circles: circles,
            selectedCircleID: selectedMembership.circleID,
            prompt: currentPrompt,
            endOfDayPrompt: endOfDayPrompt
        )
    }

    func circleContext(circleID: UUID) async throws -> CircleContext {
        let circle = try await fetchCircle(id: circleID, inviteCode: "")
        let prompts = try await fetchCurrentPrompts(circle: circle)
        return CircleContext(circle: circle, prompt: prompts.daily, endOfDayPrompt: prompts.endOfDay)
    }

    func circleContext(promptID: UUID) async throws -> CircleContext {
        let rows: [PromptRow] = try await client
            .from("daily_prompts")
            .select()
            .eq("id", value: promptID)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { throw BlessingError.circleNotFound }
        let circle = try await fetchCircle(id: row.circleID, inviteCode: "")
        let selectedPrompt = prompt(from: row, timeZoneIdentifier: circle.timeZoneIdentifier)
        let current = try await fetchCurrentPrompts(circle: circle)
        return CircleContext(
            circle: circle,
            prompt: selectedPrompt.kind == .daily ? selectedPrompt : current.daily,
            endOfDayPrompt: selectedPrompt.kind == .endOfDay ? selectedPrompt : current.endOfDay
        )
    }

    func timeline(circleID: UUID, viewerID: UUID, now: Date) async throws -> [TimelineLane] {
        let circle = try await fetchCircle(id: circleID, inviteCode: "")
        let currentLocalDate = Self.localDateString(
            at: now,
            timeZoneIdentifier: circle.timeZoneIdentifier
        )
        let promptRows: [PromptRow] = try await client
            .from("daily_prompts")
            .select()
            .eq("circle_id", value: circleID)
            .lte("local_date", value: currentLocalDate)
            .order("local_date", ascending: false)
            .execute()
            .value
        let visiblePromptRows = promptRows.filter { $0.kind == .daily || $0.startsAt <= now }
        guard !visiblePromptRows.isEmpty else {
            return circle.members.map {
                TimelineLane(
                    member: $0,
                    events: [TimelineEvent(memberID: $0.id, date: $0.joinedAt, status: .joinedCircle)]
                )
            }
        }

        let blessingRows: [BlessingRow] = try await client
            .from("blessings")
            .select()
            .in("prompt_id", values: visiblePromptRows.map(\.id))
            .execute()
            .value
        var blessings: [Blessing] = []
        for row in blessingRows {
            blessings.append(try await blessing(from: row, circleID: circleID))
        }

        let calendar = circleCalendar(circle)
        let nextDailyStart = visiblePromptRows
            .filter { $0.kind == .daily && $0.startsAt > now }
            .map(\.startsAt)
            .min()

        return circle.members.map { member in
            var events = visiblePromptRows
                .filter {
                    $0.startsAt >= member.joinedAt
                        || calendar.isDate($0.startsAt, inSameDayAs: member.joinedAt)
                }
                .map { row -> TimelineEvent in
                    let prompt = prompt(from: row, timeZoneIdentifier: circle.timeZoneIdentifier)
                    let match = blessings.first { $0.promptID == prompt.id && $0.authorID == member.id }
                    let isToday = row.localDate == currentLocalDate
                    let viewerHasSubmitted = blessings.contains {
                        $0.promptID == prompt.id && $0.authorID == viewerID
                    }
                    let newerDailyHasStarted = visiblePromptRows.contains {
                        $0.kind == .daily
                            && $0.startsAt > prompt.startsAt
                            && $0.startsAt <= now
                    }
                    let endOfDayOpen = prompt.kind == .endOfDay
                        && prompt.phase(at: now) == .open
                        && !newerDailyHasStarted
                        && nextDailyStart.map { now < $0 } ?? true
                    let requiresSubmissionGate = isToday || endOfDayOpen
                    let status: TimelineStatus
                    if requiresSubmissionGate && member.id != viewerID && !viewerHasSubmitted {
                        status = .locked
                    } else if let match {
                        status = .blessing(match)
                    } else if prompt.kind == .endOfDay && endOfDayOpen {
                        status = .waiting
                    } else if isToday && prompt.kind == .daily && (prompt.phase(at: now) != .closed || circle.allowsLateBlessings || FirstDaySubmissionPolicy.isEligible(memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle, now: now)) {
                        status = .waiting
                    } else {
                        status = .missed
                    }
                    return TimelineEvent(
                        memberID: member.id,
                        date: prompt.localDate,
                        status: status,
                        promptKind: prompt.kind
                    )
                }
            events.append(TimelineEvent(memberID: member.id, date: member.joinedAt, status: .joinedCircle))
            return TimelineLane(member: member, events: events)
        }
    }

    func beginBlessingEntry(promptID: UUID, memberID _: UUID, now _: Date) async throws {
        _ = try await client.rpc(
            "begin_blessing_entry",
            params: BeginBlessingEntryParams(promptID: promptID)
        ).execute()
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
        if mode == .video, photoURL != nil { throw BlessingError.emptyBlessing }
        let promptRow: PromptRow = try await client
            .from("daily_prompts")
            .select()
            .eq("id", value: promptID)
            .single()
            .execute()
            .value
        var audioPath: String?
        var videoPath: String?
        var thumbnailPath: String?
        var photoPath: String?
        let basePath = Self.mediaPath(
            circleID: promptRow.circleID,
            promptID: promptID,
            userID: authorID
        )
        if let audioURL {
            audioPath = "\(basePath)/voice-\(UUID().uuidString.lowercased()).caf"
            try await upload(fileURL: audioURL, path: audioPath!, contentType: "audio/x-caf")
        }
        if let videoURL {
            videoPath = "\(basePath)/video-\(UUID().uuidString.lowercased()).mov"
            try await upload(fileURL: videoURL, path: videoPath!, contentType: "video/quicktime")
            let thumbnailURL = try await CaptureMediaStore.persistVideoThumbnail(from: videoURL)
            thumbnailPath = "\(basePath)/thumbnail-\(UUID().uuidString.lowercased()).jpg"
            try await upload(fileURL: thumbnailURL, path: thumbnailPath!, contentType: "image/jpeg")
        }
        if let photoURL {
            photoPath = "\(basePath)/photo-\(UUID().uuidString.lowercased()).jpg"
            try await upload(fileURL: photoURL, path: photoPath!, contentType: "image/jpeg")
        }

        let row: BlessingRow
        if mode == .video {
            row = try await client.rpc(
                "finalize_video_blessing",
                params: FinalizeVideoParams(
                    promptID: promptID,
                    videoPath: videoPath,
                    transcript: body,
                    thumbnailPath: thumbnailPath,
                    reference: scriptureReference
                )
            )
            .single()
            .execute()
            .value
        } else {
            row = try await client.rpc(
                "submit_text_blessing",
                params: SubmitTextParams(
                    promptID: promptID,
                    mode: mode.rawValue,
                    body: body,
                    audioPath: audioPath,
                    photoPath: photoPath,
                    reference: scriptureReference
                )
            )
            .single()
            .execute()
            .value
        }
        return try await blessing(from: row, circleID: promptRow.circleID)
    }

    func updateBlessing(
        blessingID: UUID,
        authorID _: UUID,
        body: String,
        scriptureReference: ScriptureReference?,
        now _: Date
    ) async throws -> Blessing {
        let row: BlessingRow = try await client.rpc(
            "update_blessing",
            params: UpdateBlessingParams(
                blessingID: blessingID,
                body: body,
                reference: scriptureReference
            )
        )
        .single()
        .execute()
        .value
        let relationship = try await fetchBlessing(id: blessingID)
        return try await blessing(from: row, circleID: relationship.circleID)
    }

    func joinCircle(code: String, memberID: UUID) async throws -> CircleGroup {
        let row: CircleRow = try await client.rpc(
            "join_circle",
            params: ["p_invite_code": code]
        )
        .single()
        .execute()
        .value
        return try await fetchCircle(id: row.id, inviteCode: code.uppercased())
    }

    func createCircle(configuration: CircleConfiguration, member: Member) async throws -> CircleGroup {
        let code = Self.inviteCode()
        let row: CircleRow = try await client.rpc(
            "create_circle",
            params: CreateCircleParams(
                name: configuration.name,
                inviteCode: code,
                timeZone: configuration.timeZoneIdentifier,
                windowStart: Self.postgresTime(minutes: configuration.randomWindowStartMinutes),
                windowEnd: Self.postgresTime(minutes: configuration.randomWindowEndMinutes),
                responseWindowMinutes: configuration.responseWindowMinutes,
                allowLateBlessings: configuration.allowsLateBlessings,
                repeatWindowMinutes: configuration.repeatWindowMinutes,
                endOfDayTime: Self.postgresTime(minutes: configuration.endOfDayMinutes)
            )
        )
        .single()
        .execute()
        .value
        return try await fetchCircle(id: row.id, inviteCode: code)
    }

    func regenerateInviteCode(circleID: UUID, ownerID: UUID) async throws -> CircleGroup {
        let code = Self.inviteCode()
        let row: CircleRow = try await client.rpc(
            "regenerate_circle_invite_code",
            params: RegenerateInviteCodeParams(circleID: circleID, inviteCode: code)
        )
        .single()
        .execute()
        .value
        return try await fetchCircle(id: row.id, inviteCode: code)
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
        repeatWindowMinutes: Int,
        endOfDayMinutes: Int
    ) async throws -> CircleGroup {
        let row: CircleRow = try await client.rpc(
            "update_circle_settings",
            params: UpdateCircleSettingsParams(
                circleID: circleID,
                name: name,
                timeZone: timeZoneIdentifier,
                windowStart: Self.postgresTime(minutes: randomWindowStartMinutes),
                windowEnd: Self.postgresTime(minutes: randomWindowEndMinutes),
                responseWindowMinutes: responseWindowMinutes,
                allowLateBlessings: allowsLateBlessings,
                repeatWindowMinutes: repeatWindowMinutes,
                endOfDayTime: Self.postgresTime(minutes: endOfDayMinutes)
            )
        )
        .single()
        .execute()
        .value
        return try await fetchCircle(id: row.id, inviteCode: "")
    }

    func updateCirclePhoto(circleID: UUID, ownerID _: UUID, photoURL: URL?) async throws -> CircleGroup {
        let photoPath: String?
        if let photoURL {
            guard photoURL.isFileURL else { throw BlessingError.cameraUnavailable }
            photoPath = "\(circleID.uuidString.lowercased())/circle.jpg"
            try await uploadCirclePhoto(fileURL: photoURL, path: photoPath!)
        } else {
            photoPath = nil
        }
        let row: CircleRow = try await client.rpc(
            "update_circle_photo",
            params: UpdateCirclePhotoParams(circleID: circleID, photoPath: photoPath)
        )
        .single()
        .execute()
        .value
        if photoPath == nil {
            _ = try? await client.storage.from(circlePhotoBucket).remove(
                paths: ["\(circleID.uuidString.lowercased())/circle.jpg"]
            )
        }
        return try await fetchCircle(id: row.id, inviteCode: "")
    }

    func updateCircleActivityNotifications(
        circleID: UUID,
        memberID _: UUID,
        enabled: Bool
    ) async throws {
        _ = try await client.rpc(
            "update_circle_activity_notifications",
            params: UpdateCircleActivityNotificationsParams(circleID: circleID, enabled: enabled)
        ).execute()
    }

    func updateEndOfDayNotifications(
        circleID: UUID,
        memberID _: UUID,
        enabled: Bool
    ) async throws {
        _ = try await client.rpc(
            "update_end_of_day_notifications",
            params: UpdateEndOfDayNotificationsParams(circleID: circleID, enabled: enabled)
        ).execute()
    }

    func forceCirclePrompt(
        circleID: UUID,
        ownerID: UUID,
        now: Date
    ) async throws -> CirclePromptDispatch {
        let response: ForcePromptResponse = try await client.functions.invoke(
            "dispatch-prompts",
            options: FunctionInvokeOptions(
                body: ForcePromptRequest(action: "force", circleID: circleID)
            )
        )
        let context = try await circleContext(circleID: circleID)
        guard let prompt = context.prompt, prompt.id == response.promptID else {
            throw BlessingError.circleNotFound
        }
        return CirclePromptDispatch(
            prompt: prompt,
            deliveredNotifications: response.delivered,
            attemptedNotifications: response.attempted,
            registeredDevices: response.registeredDevices,
            memberCount: response.memberCount
        )
    }

    func updateBibleVersion(memberID: UUID, versionID: String) async throws -> Member {
        let row: ProfileRow = try await client.rpc(
            "update_bible_version",
            params: ["p_version_id": versionID]
        )
        .single()
        .execute()
        .value
        return try await member(from: row, joinedAt: .distantPast)
    }

    func updateProfile(memberID: UUID, displayName: String, avatarURL: URL?) async throws -> Member {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 60 else { throw BlessingError.invalidInviteCode }
        var avatarPath: String?
        if let avatarURL {
            avatarPath = "\(memberID.uuidString.lowercased())/avatar.jpg"
            try await uploadAvatar(fileURL: avatarURL, path: avatarPath!)
        }
        let row: ProfileRow
        if let avatarPath {
            row = try await client.from("profiles")
                .update(ProfileUpdate(displayName: cleaned, avatarPath: avatarPath))
                .eq("id", value: memberID).select().single().execute().value
        } else {
            row = try await client.from("profiles")
                .update(ProfileNameUpdate(displayName: cleaned))
                .eq("id", value: memberID).select().single().execute().value
        }
        return try await member(from: row, joinedAt: .distantPast)
    }

    private func uploadAvatar(fileURL: URL, path: String) async throws {
        let client = client
        let avatarBucket = avatarBucket
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                _ = try await client.storage.from(avatarBucket).upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw BlessingError.profileSaveTimedOut
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func uploadCirclePhoto(fileURL: URL, path: String) async throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        _ = try await client.storage.from(circlePhotoBucket).upload(
            path,
            data: data,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
    }

    func transferCircleOwnership(
        circleID: UUID,
        ownerID: UUID,
        newOwnerID: UUID
    ) async throws -> CircleGroup {
        let row: CircleRow = try await client.rpc(
            "transfer_circle_ownership",
            params: [
                "p_circle_id": circleID,
                "p_new_owner_id": newOwnerID,
            ]
        )
        .single()
        .execute()
        .value
        return try await fetchCircle(id: row.id, inviteCode: "")
    }

    func removeCircleMember(circleID: UUID, ownerID: UUID, memberID: UUID) async throws -> CircleGroup {
        let row: CircleRow = try await client.rpc(
            "remove_circle_member",
            params: [
                "p_circle_id": circleID,
                "p_member_id": memberID,
            ]
        )
        .single()
        .execute()
        .value
        return try await fetchCircle(id: row.id, inviteCode: "")
    }

    func recentBlessings(authorID: UUID, submittedAfter: Date) async throws -> [Blessing] {
        let rows: [BlessingRow] = try await client
            .from("blessings")
            .select("*, daily_prompts!inner(circle_id)")
            .eq("author_id", value: authorID)
            .gte("submitted_at", value: ISO8601DateFormatter().string(from: submittedAfter))
            .order("submitted_at", ascending: false)
            .execute()
            .value
        var result: [Blessing] = []
        for row in rows {
            guard let circleID = row.dailyPrompts?.circleID else { continue }
            result.append(try await blessing(from: row, circleID: circleID))
        }
        return result
    }

    func repeatBlessing(
        sourceBlessingID: UUID,
        targetPromptID: UUID,
        authorID: UUID,
        now: Date
    ) async throws -> Blessing {
        let promptRow: PromptRow = try await client
            .from("daily_prompts")
            .select()
            .eq("id", value: targetPromptID)
            .single()
            .execute()
            .value
        let row: BlessingRow = try await client.rpc(
            "repeat_blessing",
            params: [
                "p_source_blessing_id": sourceBlessingID,
                "p_target_prompt_id": targetPromptID,
            ]
        )
        .single()
        .execute()
        .value
        return try await blessing(from: row, circleID: promptRow.circleID)
    }

    func leaveCircle(circleID: UUID, memberID: UUID) async throws {
        _ = try await client.rpc(
            "leave_circle",
            params: ["p_circle_id": circleID]
        ).execute()
    }

    func responses(blessingID: UUID, viewerID: UUID) async throws -> [BlessingResponse] {
        let blessingRow = try await fetchBlessing(id: blessingID)
        let rows: [ResponseRow] = try await client
            .from("blessing_responses")
            .select()
            .eq("blessing_id", value: blessingID)
            .order("submitted_at")
            .execute()
            .value
        var result: [BlessingResponse] = []
        for row in rows {
            result.append(try await response(from: row, circleID: blessingRow.circleID))
        }
        return result
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
        let blessingRow = try await fetchBlessing(id: blessingID)
        var audioPath: String?
        if let audioURL {
            let basePath = Self.mediaPath(
                circleID: circleID,
                promptID: blessingRow.promptID,
                userID: authorID
            )
            audioPath = "\(basePath)/responses/\(blessingID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).caf"
            try await upload(fileURL: audioURL, path: audioPath!, contentType: "audio/x-caf")
        }
        let row: ResponseRow = try await client.rpc(
            "submit_blessing_response",
            params: SubmitResponseParams(
                blessingID: blessingID,
                mode: mode.rawValue,
                body: body,
                audioPath: audioPath
            )
        )
        .single()
        .execute()
        .value
        return try await response(from: row, circleID: circleID)
    }

    func timelineUpdates(circleID: UUID) async throws -> AsyncStream<Void> {
        let channel = client.channel("circle-\(circleID.uuidString.lowercased())")
        let blessingChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "blessings")
        let responseChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "blessing_responses")
        let promptChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "daily_prompts",
            filter: .eq("circle_id", value: circleID)
        )
        let membershipChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "circle_members",
            filter: .eq("circle_id", value: circleID)
        )
        try await channel.subscribeWithError()

        return AsyncStream { continuation in
            let tasks = [
                Task { for await _ in blessingChanges { continuation.yield() } },
                Task { for await _ in responseChanges { continuation.yield() } },
                Task { for await _ in promptChanges { continuation.yield() } },
                Task { for await _ in membershipChanges { continuation.yield() } },
            ]
            continuation.onTermination = { _ in
                tasks.forEach { $0.cancel() }
                Task { await self.client.removeChannel(channel) }
            }
        }
    }

    func registerDevice(
        installationID: UUID,
        apnsToken: String?,
        pushToStartToken: String?,
        environment: String
    ) async throws {
        _ = try await client.rpc(
            "register_device",
            params: RegisterDeviceParams(
                installationID: installationID,
                apnsToken: apnsToken,
                pushToStartToken: pushToStartToken,
                environment: environment
            )
        ).execute()
    }

    func registerActivity(
        promptID: UUID,
        activityID: String,
        pushToken: String,
        environment: String
    ) async throws {
        _ = try await client.rpc(
            "register_activity",
            params: RegisterActivityParams(
                promptID: promptID,
                activityID: activityID,
                pushToken: pushToken,
                environment: environment
            )
        ).execute()
    }

    private func fetchProfile(userID: UUID) async throws -> ProfileRow {
        try await client.from("profiles").select().eq("id", value: userID).single().execute().value
    }

    private func fetchCircle(id: UUID, inviteCode: String) async throws -> CircleGroup {
        let viewerID = try await client.auth.session.user.id
        let row: CircleRow = try await client.from("circles").select().eq("id", value: id).single().execute().value
        let membershipRows: [MembershipRow] = try await client
            .from("circle_members")
            .select()
            .eq("circle_id", value: id)
            .is("removed_at", value: nil)
            .order("joined_at")
            .execute()
            .value
        let ids: [any PostgrestFilterValue] = membershipRows.map(\.userID)
        let profiles: [ProfileRow] = ids.isEmpty ? [] : try await client
            .from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
        var members: [Member] = []
        for membership in membershipRows {
            guard let profile = profiles.first(where: { $0.id == membership.userID }) else { continue }
            members.append(try await member(from: profile, joinedAt: membership.joinedAt))
        }
        return CircleGroup(
            id: row.id,
            name: row.name,
            inviteCode: inviteCode,
            ownerID: row.ownerID,
            members: members,
            timeZoneIdentifier: row.timeZone,
            randomWindowStartMinutes: Self.minutes(postgresTime: row.windowStart),
            randomWindowEndMinutes: Self.minutes(postgresTime: row.windowEnd),
            responseWindowMinutes: row.responseWindowMinutes,
            allowsLateBlessings: row.allowLateBlessings,
            repeatWindowMinutes: row.repeatWindowMinutes,
            endOfDayMinutes: Self.minutes(postgresTime: row.endOfDayTime),
            photoURL: try await circlePhotoSignedURL(path: row.photoPath),
            circleActivityNotificationsEnabled: membershipRows
                .first(where: { $0.userID == viewerID })?
                .notifyOnCircleActivity ?? true,
            endOfDayNotificationsEnabled: membershipRows
                .first(where: { $0.userID == viewerID })?
                .notifyOnEndOfDay ?? true
        )
    }

    private func circlePhotoSignedURL(path: String?) async throws -> URL? {
        guard let path else { return nil }
        return try await client.storage.from(circlePhotoBucket).createSignedURL(path: path, expiresIn: 86_400)
    }

    private func fetchCurrentPrompts(
        circle: CircleGroup,
        now: Date = .now
    ) async throws -> (daily: DailyPrompt?, endOfDay: DailyPrompt?) {
        let localDate = Self.localDateString(
            at: now,
            timeZoneIdentifier: circle.timeZoneIdentifier
        )
        let currentRows: [PromptRow] = try await client
            .from("daily_prompts")
            .select()
            .eq("circle_id", value: circle.id)
            .eq("local_date", value: localDate)
            .execute()
            .value
        let activeEndRows: [PromptRow] = try await client
            .from("daily_prompts")
            .select()
            .eq("circle_id", value: circle.id)
            .eq("kind", value: PromptKind.endOfDay.rawValue)
            .lte("starts_at", value: now)
            .gt("ends_at", value: now)
            .order("starts_at", ascending: false)
            .limit(1)
            .execute()
            .value
        let dailyRow = currentRows.first { $0.kind == .daily }
        let scheduledEndRow = currentRows.first { $0.kind == .endOfDay }
        let activeEndRow = activeEndRows.first.flatMap { row -> PromptRow? in
            if let dailyRow,
               dailyRow.startsAt > row.startsAt,
               dailyRow.startsAt <= now {
                return nil
            }
            return row
        }
        let endRow = activeEndRow ?? scheduledEndRow
        return (
            dailyRow.map { prompt(from: $0, timeZoneIdentifier: circle.timeZoneIdentifier) },
            endRow.map { prompt(from: $0, timeZoneIdentifier: circle.timeZoneIdentifier) }
        )
    }

    private func fetchBlessing(id: UUID) async throws -> BlessingWithCircleRow {
        try await client
            .from("blessings")
            .select("*, daily_prompts!inner(circle_id)")
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    private func blessing(from row: BlessingRow, circleID: UUID) async throws -> Blessing {
        Blessing(
            id: row.id,
            circleID: circleID,
            promptID: row.promptID,
            authorID: row.authorID,
            captureMode: CaptureMode(rawValue: row.captureMode) ?? .typed,
            body: row.body,
            audioURL: try await signedURL(path: row.audioPath),
            videoURL: try await signedURL(path: row.videoPath),
            submittedAt: row.submittedAt,
            isLate: row.isLate,
            scriptureReference: row.scriptureReference,
            repeatedFromBlessingID: row.repeatedFromBlessingID,
            photoURL: try await signedURL(path: row.photoPath),
            editedAt: row.editedAt
        )
    }

    private func response(from row: ResponseRow, circleID: UUID) async throws -> BlessingResponse {
        BlessingResponse(
            id: row.id,
            blessingID: row.blessingID,
            circleID: circleID,
            authorID: row.authorID,
            mode: ResponseMode(rawValue: row.mode) ?? .typed,
            body: row.body,
            audioURL: try await signedURL(path: row.audioPath),
            submittedAt: row.submittedAt
        )
    }

    private func signedURL(path: String?) async throws -> URL? {
        guard let path else { return nil }
        return try await client.storage.from(mediaBucket).createSignedURL(path: path, expiresIn: 3_600)
    }

    private func upload(fileURL: URL, path: String, contentType: String) async throws {
        let options = FileOptions(contentType: contentType, upsert: false)
        if contentType.hasPrefix("video/") {
            _ = try await client.storage.from(mediaBucket).upload(path, fileURL: fileURL, options: options)
        } else {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            _ = try await client.storage.from(mediaBucket).upload(path, data: data, options: options)
        }
    }

    private func prompt(from row: PromptRow, timeZoneIdentifier: String) -> DailyPrompt {
        DailyPrompt(
            id: row.id,
            circleID: row.circleID,
            localDate: row.localDateValue(timeZoneIdentifier: timeZoneIdentifier),
            startsAt: row.startsAt,
            endsAt: row.endsAt,
            kind: row.kind
        )
    }

    private func member(from row: ProfileRow, joinedAt: Date) async throws -> Member {
        let parts = row.displayName.split(separator: " ")
        let initials = parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return Member(
            id: row.id,
            displayName: row.displayName,
            initials: initials.isEmpty ? "BC" : initials,
            tintSeed: row.id.uuidString.utf8.reduce(0) { $0 + Int($1) },
            bibleVersionID: row.bibleVersionID,
            joinedAt: joinedAt,
            avatarURL: try await avatarSignedURL(path: row.avatarPath)
        )
    }

    private func avatarSignedURL(path: String?) async throws -> URL? {
        guard let path else { return nil }
        return try await client.storage.from(avatarBucket).createSignedURL(path: path, expiresIn: 86_400)
    }

    private func circleCalendar(_ circle: CircleGroup) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: circle.timeZoneIdentifier) ?? .current
        return calendar
    }

    private static func inviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }

    static func mediaPath(circleID: UUID, promptID: UUID, userID: UUID) -> String {
        [circleID, promptID, userID]
            .map { $0.uuidString.lowercased() }
            .joined(separator: "/")
    }

    private static func minutes(postgresTime: String) -> Int {
        let parts = postgresTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private static func postgresTime(minutes: Int) -> String {
        String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }

    private static func localDateString(at date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct ProfileRow: Codable, Sendable {
    let id: UUID
    let displayName: String
    let bibleVersionID: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case bibleVersionID = "bible_version_id"
        case avatarPath = "avatar_path"
    }
}

private struct ProfileUpdate: Encodable, Sendable {
    let displayName: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}

private struct ProfileNameUpdate: Encodable, Sendable {
    let displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

private struct MembershipRow: Codable, Sendable {
    let circleID: UUID
    let userID: UUID
    let joinedAt: Date
    let notifyOnCircleActivity: Bool?
    let notifyOnEndOfDay: Bool?

    enum CodingKeys: String, CodingKey {
        case circleID = "circle_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
        case notifyOnCircleActivity = "notify_on_circle_activity"
        case notifyOnEndOfDay = "notify_on_end_of_day"
    }
}

private struct CircleRow: Codable, Sendable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let timeZone: String
    let windowStart: String
    let windowEnd: String
    let responseWindowMinutes: Int
    let allowLateBlessings: Bool
    let repeatWindowMinutes: Int
    let endOfDayTime: String
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case timeZone = "time_zone"
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case responseWindowMinutes = "response_window_minutes"
        case allowLateBlessings = "allow_late_blessings"
        case repeatWindowMinutes = "repeat_window_minutes"
        case endOfDayTime = "end_of_day_time"
        case photoPath = "photo_path"
    }
}

private struct PromptRow: Codable, Sendable {
    let id: UUID
    let circleID: UUID
    let localDate: String
    let startsAt: Date
    let endsAt: Date
    let kind: PromptKind

    func localDateValue(timeZoneIdentifier: String) -> Date {
        CircleLocalDay.date(from: localDate, timeZoneIdentifier: timeZoneIdentifier) ?? startsAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case circleID = "circle_id"
        case localDate = "local_date"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case kind
    }
}

private struct ForcePromptRequest: Encodable, Sendable {
    let action: String
    let circleID: UUID

    enum CodingKeys: String, CodingKey {
        case action
        case circleID = "circle_id"
    }
}

private struct ForcePromptResponse: Decodable, Sendable {
    let promptID: UUID
    let delivered: Int
    let attempted: Int
    let registeredDevices: Int
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case delivered, attempted
        case promptID = "promptID"
        case registeredDevices
        case memberCount
    }
}

private struct BlessingRow: Codable, Sendable {
    let id: UUID
    let promptID: UUID
    let authorID: UUID
    let captureMode: String
    let body: String?
    let audioPath: String?
    let videoPath: String?
    let photoPath: String?
    let submittedAt: Date
    let isLate: Bool
    let scriptureBookSlug: String?
    let scriptureBookName: String?
    let scriptureChapter: Int?
    let scriptureVerseStart: Int?
    let scriptureVerseEnd: Int?
    let repeatedFromBlessingID: UUID?
    let editedAt: Date?
    let dailyPrompts: PromptCircleRow?

    var scriptureReference: ScriptureReference? {
        guard let scriptureBookSlug, let scriptureBookName, let scriptureChapter,
              let scriptureVerseStart, let scriptureVerseEnd else { return nil }
        return ScriptureReference(
            bookSlug: scriptureBookSlug,
            bookName: scriptureBookName,
            chapter: scriptureChapter,
            verseStart: scriptureVerseStart,
            verseEnd: scriptureVerseEnd
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, body
        case promptID = "prompt_id"
        case authorID = "author_id"
        case captureMode = "capture_mode"
        case audioPath = "audio_path"
        case videoPath = "video_path"
        case photoPath = "photo_path"
        case submittedAt = "submitted_at"
        case isLate = "is_late"
        case scriptureBookSlug = "scripture_book_slug"
        case scriptureBookName = "scripture_book_name"
        case scriptureChapter = "scripture_chapter"
        case scriptureVerseStart = "scripture_verse_start"
        case scriptureVerseEnd = "scripture_verse_end"
        case repeatedFromBlessingID = "repeated_from_blessing_id"
        case editedAt = "edited_at"
        case dailyPrompts = "daily_prompts"
    }
}

private struct PromptCircleRow: Codable, Sendable {
    let circleID: UUID
    enum CodingKeys: String, CodingKey { case circleID = "circle_id" }
}

private struct BlessingWithCircleRow: Codable, Sendable {
    let promptID: UUID
    let dailyPrompts: PromptCircleRow
    var circleID: UUID { dailyPrompts.circleID }

    enum CodingKeys: String, CodingKey {
        case promptID = "prompt_id"
        case dailyPrompts = "daily_prompts"
    }
}

private struct ResponseRow: Codable, Sendable {
    let id: UUID
    let blessingID: UUID
    let authorID: UUID
    let mode: String
    let body: String
    let audioPath: String?
    let submittedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, mode, body
        case blessingID = "blessing_id"
        case authorID = "author_id"
        case audioPath = "audio_path"
        case submittedAt = "submitted_at"
    }
}

private struct CreateCircleParams: Encodable, Sendable {
    let name: String
    let inviteCode: String
    let timeZone: String
    let windowStart: String
    let windowEnd: String
    let responseWindowMinutes: Int
    let allowLateBlessings: Bool
    let repeatWindowMinutes: Int
    let endOfDayTime: String
    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case inviteCode = "p_invite_code"
        case timeZone = "p_time_zone"
        case windowStart = "p_window_start"
        case windowEnd = "p_window_end"
        case responseWindowMinutes = "p_response_window_minutes"
        case allowLateBlessings = "p_allow_late_blessings"
        case repeatWindowMinutes = "p_repeat_window_minutes"
        case endOfDayTime = "p_end_of_day_time"
    }
}

private struct RegenerateInviteCodeParams: Encodable, Sendable {
    let circleID: UUID
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case circleID = "p_circle_id"
        case inviteCode = "p_invite_code"
    }
}

private struct UpdateCircleSettingsParams: Encodable, Sendable {
    let circleID: UUID
    let name: String
    let timeZone: String
    let windowStart: String
    let windowEnd: String
    let responseWindowMinutes: Int
    let allowLateBlessings: Bool
    let repeatWindowMinutes: Int
    let endOfDayTime: String
    enum CodingKeys: String, CodingKey {
        case circleID = "p_circle_id"
        case name = "p_name"
        case timeZone = "p_time_zone"
        case windowStart = "p_window_start"
        case windowEnd = "p_window_end"
        case responseWindowMinutes = "p_response_window_minutes"
        case allowLateBlessings = "p_allow_late_blessings"
        case repeatWindowMinutes = "p_repeat_window_minutes"
        case endOfDayTime = "p_end_of_day_time"
    }
}

private struct UpdateCirclePhotoParams: Encodable, Sendable {
    let circleID: UUID
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case circleID = "p_circle_id"
        case photoPath = "p_photo_path"
    }
}

private struct UpdateCircleActivityNotificationsParams: Encodable, Sendable {
    let circleID: UUID
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case circleID = "p_circle_id"
        case enabled = "p_enabled"
    }
}

private struct UpdateEndOfDayNotificationsParams: Encodable, Sendable {
    let circleID: UUID
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case circleID = "p_circle_id"
        case enabled = "p_enabled"
    }
}

private struct BeginBlessingEntryParams: Encodable, Sendable {
    let promptID: UUID

    enum CodingKeys: String, CodingKey {
        case promptID = "p_prompt_id"
    }
}

private struct UpdateBlessingParams: Encodable, Sendable {
    let blessingID: UUID
    let body: String
    let scriptureBookSlug: String?
    let scriptureBookName: String?
    let scriptureChapter: Int?
    let scriptureVerseStart: Int?
    let scriptureVerseEnd: Int?

    init(blessingID: UUID, body: String, reference: ScriptureReference?) {
        self.blessingID = blessingID
        self.body = body
        scriptureBookSlug = reference?.bookSlug
        scriptureBookName = reference?.bookName
        scriptureChapter = reference?.chapter
        scriptureVerseStart = reference?.verseStart
        scriptureVerseEnd = reference?.verseEnd
    }

    enum CodingKeys: String, CodingKey {
        case blessingID = "p_blessing_id"
        case body = "p_body"
        case scriptureBookSlug = "p_scripture_book_slug"
        case scriptureBookName = "p_scripture_book_name"
        case scriptureChapter = "p_scripture_chapter"
        case scriptureVerseStart = "p_scripture_verse_start"
        case scriptureVerseEnd = "p_scripture_verse_end"
    }
}

private struct SubmitTextParams: Encodable, Sendable {
    let promptID: UUID
    let mode: String
    let body: String?
    let audioPath: String?
    let photoPath: String?
    let scriptureBookSlug: String?
    let scriptureBookName: String?
    let scriptureChapter: Int?
    let scriptureVerseStart: Int?
    let scriptureVerseEnd: Int?

    init(
        promptID: UUID,
        mode: String,
        body: String?,
        audioPath: String?,
        photoPath: String?,
        reference: ScriptureReference?
    ) {
        self.promptID = promptID
        self.mode = mode
        self.body = body
        self.audioPath = audioPath
        self.photoPath = photoPath
        scriptureBookSlug = reference?.bookSlug
        scriptureBookName = reference?.bookName
        scriptureChapter = reference?.chapter
        scriptureVerseStart = reference?.verseStart
        scriptureVerseEnd = reference?.verseEnd
    }

    enum CodingKeys: String, CodingKey {
        case promptID = "p_prompt_id"
        case mode = "p_mode"
        case body = "p_body"
        case audioPath = "p_audio_path"
        case photoPath = "p_photo_path"
        case scriptureBookSlug = "p_scripture_book_slug"
        case scriptureBookName = "p_scripture_book_name"
        case scriptureChapter = "p_scripture_chapter"
        case scriptureVerseStart = "p_scripture_verse_start"
        case scriptureVerseEnd = "p_scripture_verse_end"
    }
}

private struct FinalizeVideoParams: Encodable, Sendable {
    let promptID: UUID
    let videoPath: String?
    let transcript: String?
    let thumbnailPath: String?
    let scriptureBookSlug: String?
    let scriptureBookName: String?
    let scriptureChapter: Int?
    let scriptureVerseStart: Int?
    let scriptureVerseEnd: Int?

    init(
        promptID: UUID,
        videoPath: String?,
        transcript: String?,
        thumbnailPath: String?,
        reference: ScriptureReference?
    ) {
        self.promptID = promptID
        self.videoPath = videoPath
        self.transcript = transcript
        self.thumbnailPath = thumbnailPath
        scriptureBookSlug = reference?.bookSlug
        scriptureBookName = reference?.bookName
        scriptureChapter = reference?.chapter
        scriptureVerseStart = reference?.verseStart
        scriptureVerseEnd = reference?.verseEnd
    }

    enum CodingKeys: String, CodingKey {
        case promptID = "p_prompt_id"
        case videoPath = "p_video_path"
        case transcript = "p_transcript"
        case thumbnailPath = "p_thumbnail_path"
        case scriptureBookSlug = "p_scripture_book_slug"
        case scriptureBookName = "p_scripture_book_name"
        case scriptureChapter = "p_scripture_chapter"
        case scriptureVerseStart = "p_scripture_verse_start"
        case scriptureVerseEnd = "p_scripture_verse_end"
    }
}

private struct SubmitResponseParams: Encodable, Sendable {
    let blessingID: UUID
    let mode: String
    let body: String
    let audioPath: String?
    enum CodingKeys: String, CodingKey {
        case blessingID = "p_blessing_id"
        case mode = "p_mode"
        case body = "p_body"
        case audioPath = "p_audio_path"
    }
}

private struct RegisterDeviceParams: Encodable, Sendable {
    let installationID: UUID
    let apnsToken: String?
    let pushToStartToken: String?
    let environment: String

    enum CodingKeys: String, CodingKey {
        case installationID = "p_installation_id"
        case apnsToken = "p_apns_token"
        case pushToStartToken = "p_push_to_start_token"
        case environment = "p_environment"
    }
}

private struct RegisterActivityParams: Encodable, Sendable {
    let promptID: UUID
    let activityID: String
    let pushToken: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case promptID = "p_prompt_id"
        case activityID = "p_activity_id"
        case pushToken = "p_push_token"
        case environment = "p_environment"
    }
}
