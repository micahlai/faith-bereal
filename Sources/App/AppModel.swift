import Foundation
import Observation
import UIKit
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case signedOut
        case failed(String)
    }

    private let repository: any BlessingRepository
    private let bibleService: any BibleTextProviding
    private let authentication: (any AuthenticationProviding)?
    private let activityController = PromptActivityController()
    private var realtimeTask: Task<Void, Never>?
    private var widgetSnapshotTask: Task<Void, Never>?
    private var remoteServicesConfigured = false
    private var apnsToken: String?
    private var pushToStartToken: String?

    var loadState: LoadState = .idle
    var currentUser: Member?
    var circles: [CircleGroup] = []
    var circle: CircleGroup?
    var prompt: DailyPrompt?
    var lanes: [TimelineLane] = []
    var selectedTab = 0
    var isCapturePresented = false
    var isSubmitting = false
    var isSwitchingCircle = false
    var message: String?
    var submittedBlessing: Blessing?
    var deepLinkedBlessing: BlessingFeedItem?
    var isForcingCirclePrompt = false
#if DEBUG
    var isRunningDebugAction = false
    var isDebugPromptPreview = false
#endif
    var appearancePreference: AppearancePreference {
        didSet { UserDefaults.standard.set(appearancePreference.rawValue, forKey: Self.appearanceKey) }
    }
    var appIconPreference: AppIconPreference
    var isChangingAppIcon = false
    var widgetRefreshMinutes: Int {
        didSet {
            UserDefaults.standard.set(widgetRefreshMinutes, forKey: Self.widgetRefreshKey)
            scheduleWidgetSnapshotRefresh()
        }
    }

    init(
        repository: any BlessingRepository,
        bibleService: any BibleTextProviding = BibleAPIService(),
        authentication: (any AuthenticationProviding)? = nil
    ) {
        self.repository = repository
        self.bibleService = bibleService
        self.authentication = authentication
        self.appearancePreference = AppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ""
        ) ?? .automatic
        self.appIconPreference = AppIconPreference(
            alternateIconName: UIApplication.shared.alternateIconName
        )
        let savedWidgetInterval = UserDefaults.standard.integer(forKey: Self.widgetRefreshKey)
        self.widgetRefreshMinutes = Self.widgetRefreshOptions.contains(savedWidgetInterval)
            ? savedWidgetInterval
            : 30
    }

    var hasSubmittedToday: Bool {
        currentUserBlessing() != nil
    }

    func updateAppIcon(_ preference: AppIconPreference) async {
        guard UIApplication.shared.supportsAlternateIcons else {
            message = "This device does not support changing the app icon."
            return
        }
        guard preference != appIconPreference, !isChangingAppIcon else { return }

        isChangingAppIcon = true
        defer { isChangingAppIcon = false }

        let errorMessage: String? = await withCheckedContinuation { continuation in
            UIApplication.shared.setAlternateIconName(preference.alternateIconName) { error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }

        if let errorMessage {
            appIconPreference = AppIconPreference(
                alternateIconName: UIApplication.shared.alternateIconName
            )
            message = "Couldn’t change the app icon: \(errorMessage)"
        } else {
            appIconPreference = preference
        }
    }

    func isCurrentPromptToday(at date: Date = .now) -> Bool {
        guard let prompt, let circle else { return false }
        return prompt.occursOnCircleDay(at: date, timeZoneIdentifier: circle.timeZoneIdentifier)
    }

    func currentUserBlessing(at date: Date = .now) -> Blessing? {
        guard let currentUser, let prompt, isCurrentPromptToday(at: date) else { return nil }
        if let submittedBlessing, submittedBlessing.promptID == prompt.id {
            return submittedBlessing
        }
        return lanes
            .first(where: { $0.member.id == currentUser.id })?
            .events
            .compactMap { event -> Blessing? in
                if case let .blessing(blessing) = event.status {
                    return blessing
                }
                return nil
            }
            .first(where: { $0.promptID == prompt.id })
    }

    func currentPromptBlessings(at date: Date = .now) -> [BlessingFeedItem] {
        guard let prompt, isCurrentPromptToday(at: date), currentUserBlessing(at: date) != nil else {
            return []
        }
        return lanes.compactMap { lane in
            lane.events.compactMap { event -> Blessing? in
                guard case let .blessing(blessing) = event.status,
                      blessing.promptID == prompt.id else { return nil }
                return blessing
            }
            .first
            .map { BlessingFeedItem(member: lane.member, blessing: $0) }
        }
        .sorted { lhs, rhs in
            if lhs.blessing.submittedAt != rhs.blessing.submittedAt {
                return lhs.blessing.submittedAt < rhs.blessing.submittedAt
            }
            return lhs.member.displayName.localizedCaseInsensitiveCompare(rhs.member.displayName) == .orderedAscending
        }
    }

    var canSubmitCurrentPrompt: Bool {
#if DEBUG
        guard !isDebugPromptPreview else { return false }
#endif
        guard let prompt, let circle, isCurrentPromptToday(at: .now), !hasSubmittedToday else { return false }
        let phase = prompt.phase(at: .now)
        return phase == .open || (phase == .closed && circle.allowsLateBlessings)
    }

    func bootstrap() async {
        guard loadState == .idle else { return }
        loadState = .loading
        if let authentication, await !authentication.hasSession() {
            loadState = .signedOut
            return
        }
        do {
            let bootstrap = try await repository.bootstrap()
            self.currentUser = bootstrap.currentUser
            self.circles = bootstrap.circles
            let preferredID = Self.persistedCircleID.flatMap { id in
                bootstrap.circles.contains(where: { $0.id == id }) ? id : nil
            } ?? bootstrap.selectedCircleID
            if let preferredID, preferredID != bootstrap.selectedCircleID {
                let context = try await repository.circleContext(circleID: preferredID)
                self.circle = context.circle
                self.prompt = context.prompt
            } else {
                self.circle = bootstrap.circle
                self.prompt = bootstrap.prompt
            }
            Self.persistedCircleID = self.circle?.id
            if self.circle == nil { selectedTab = 2 }
            try await refreshTimeline()
            loadState = .ready
            startRealtimeUpdates()
            await configureRemoteServices()
            if let prompt = self.prompt,
               let circle = self.circle,
               prompt.phase(at: .now) == .open {
                await startLiveActivity(for: prompt, circle: circle)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async {
        guard let authentication else { return }
        loadState = .loading
        do {
            try await authentication.signInWithApple(
                idToken: idToken,
                rawNonce: rawNonce,
                fullName: fullName
            )
            loadState = .idle
            await bootstrap()
        } catch {
            loadState = .signedOut
            message = error.localizedDescription
        }
    }

    func signOut() async {
        guard let authentication else { return }
        do {
            try await authentication.signOut()
            currentUser = nil
            circles = []
            circle = nil
            prompt = nil
            lanes = []
            realtimeTask?.cancel()
            realtimeTask = nil
            activityController.stopMonitoringTokens()
            remoteServicesConfigured = false
            loadState = .signedOut
            BlessingWidgetSnapshotStore.save(.empty)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshTimeline(now: Date = .now) async throws {
        guard let circle, let currentUser else { return }
        lanes = try await repository.timeline(circleID: circle.id, viewerID: currentUser.id, now: now)
        scheduleWidgetSnapshotRefresh(now: now)
    }

    func switchCircle(to circleID: UUID) async {
        guard circle?.id != circleID, circles.contains(where: { $0.id == circleID }) else { return }
        isSwitchingCircle = true
        defer { isSwitchingCircle = false }
        do {
            let context = try await repository.circleContext(circleID: circleID)
            let knownInviteCode = circles.first(where: { $0.id == circleID })?.inviteCode
            let resolvedCircle = context.circle.preservingInviteCode(knownInviteCode)
            circle = resolvedCircle
            prompt = context.prompt
#if DEBUG
            isDebugPromptPreview = false
#endif
            submittedBlessing = nil
            lanes = []
            if let index = circles.firstIndex(where: { $0.id == circleID }) {
                circles[index] = resolvedCircle
            }
            Self.persistedCircleID = circleID
            try await refreshTimeline()
            startRealtimeUpdates()
            if let prompt = context.prompt, prompt.phase(at: .now) == .open {
                await startLiveActivity(for: prompt, circle: resolvedCircle)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func submit(
        mode: CaptureMode,
        body: String?,
        audioURL: URL?,
        videoURL: URL?,
        photoURL: URL? = nil,
        scriptureReference: ScriptureReference?
    ) async -> Bool {
        guard let prompt, let currentUser, isCurrentPromptToday(at: .now) else {
            message = BlessingError.outsideResponseWindow.localizedDescription
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            submittedBlessing = try await repository.submit(
                promptID: prompt.id,
                authorID: currentUser.id,
                mode: mode,
                body: body,
                audioURL: audioURL,
                videoURL: videoURL,
                photoURL: photoURL,
                scriptureReference: scriptureReference,
                now: .now
            )
            try await refreshTimeline()
            await activityController.markSubmitted(promptID: prompt.id, responseCount: lanes.compactMap { lane in
                lane.events.first.flatMap { event -> Blessing? in
                    if case let .blessing(blessing) = event.status { return blessing }
                    return nil
                }
            }.count)
            message = "Your blessing is part of today's circle."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func joinCircle(code: String) async -> Bool {
        guard let currentUser else { return false }
        do {
            let joinedCircle = try await repository.joinCircle(code: code, memberID: currentUser.id)
            upsertCircle(joinedCircle)
            await switchCircle(to: joinedCircle.id)
            message = "You joined \(joinedCircle.name)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func createCircle(name: String) async -> Bool {
        guard let currentUser else { return false }
        do {
            let createdCircle = try await repository.createCircle(name: name, member: currentUser)
            upsertCircle(createdCircle)
            await switchCircle(to: createdCircle.id)
            message = "Your new circle is ready."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func updateCircleSettings(
        name: String,
        timeZoneIdentifier: String,
        randomWindowStartMinutes: Int,
        randomWindowEndMinutes: Int,
        responseWindowMinutes: Int,
        allowsLateBlessings: Bool,
        repeatWindowMinutes: Int
    ) async -> Bool {
        guard let circle, let currentUser else { return false }
        do {
            let updatedCircle = try await repository.updateCircleSettings(
                circleID: circle.id,
                ownerID: currentUser.id,
                name: name,
                timeZoneIdentifier: timeZoneIdentifier,
                randomWindowStartMinutes: randomWindowStartMinutes,
                randomWindowEndMinutes: randomWindowEndMinutes,
                responseWindowMinutes: responseWindowMinutes,
                allowsLateBlessings: allowsLateBlessings,
                repeatWindowMinutes: repeatWindowMinutes
            )
            self.circle = updatedCircle
            upsertCircle(updatedCircle)
            message = "Circle settings saved. The response length applies to future prompts."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func forceCurrentCirclePrompt(now: Date = .now) async -> Bool {
        guard let circle, let currentUser else { return false }
        guard circle.ownerID == currentUser.id else {
            message = BlessingError.notCircleOwner.localizedDescription
            return false
        }
        guard !isForcingCirclePrompt else { return false }

        isForcingCirclePrompt = true
        defer { isForcingCirclePrompt = false }

        do {
            let outcome = try await repository.forceCirclePrompt(
                circleID: circle.id,
                ownerID: currentUser.id,
                now: now
            )
            await activityController.end()
            prompt = outcome.prompt
            submittedBlessing = nil
            isCapturePresented = false
            selectedTab = 0
#if DEBUG
            isDebugPromptPreview = false
#endif
            try await refreshTimeline(now: now)

            if !usesAuthentication {
                let activityResult = await activityController.startIfNeeded(
                    prompt: outcome.prompt,
                    circle: circle,
                    requestsPushUpdates: false
                )
                message = "Local blessing test started for \(outcome.memberCount) members. \(activityResult.debugMessage)"
            } else if outcome.registeredDevices == 0 {
                message = "The blessing window is open, but no member devices are registered for notifications yet."
            } else {
                message = "The blessing window is open for \(outcome.memberCount) members. Apple accepted \(outcome.deliveredNotifications) of \(outcome.attemptedNotifications) notification and Live Activity requests across \(outcome.registeredDevices) devices."
            }
            return true
        } catch {
            message = "Couldn’t force the blessing notification: \(error.localizedDescription)"
            return false
        }
    }

    var bibleTranslations: [BibleTranslation] { BibleTranslation.publicDomain }
    var bibleTranslationGroups: [BibleTranslationGroup] { BibleTranslation.groups }
    var bibleBooks: [BibleBook] { BibleBook.all }

    var selectedBibleTranslation: BibleTranslation {
        BibleTranslation.publicDomain.first(where: { $0.id == currentUser?.bibleVersionID })
            ?? BibleTranslation.publicDomain[0]
    }

    var usesAuthentication: Bool { authentication != nil }

    func updateBibleVersion(_ versionID: String) async {
        guard let currentUser else { return }
        do {
            self.currentUser = try await repository.updateBibleVersion(
                memberID: currentUser.id,
                versionID: versionID
            )
            scheduleWidgetSnapshotRefresh()
        } catch {
            message = error.localizedDescription
        }
    }

    func transferCurrentCircleOwnership(to newOwnerID: UUID) async -> Bool {
        guard let circle, let currentUser else { return false }
        do {
            let updatedCircle = try await repository.transferCircleOwnership(
                circleID: circle.id,
                ownerID: currentUser.id,
                newOwnerID: newOwnerID
            )
            self.circle = updatedCircle
            upsertCircle(updatedCircle)
            scheduleWidgetSnapshotRefresh()
            let newOwnerName = updatedCircle.members
                .first(where: { $0.id == newOwnerID })?
                .displayName ?? "the new owner"
            message = "Ownership transferred to \(newOwnerName)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func removeMemberFromCurrentCircle(_ memberID: UUID) async -> Bool {
        guard let circle, let currentUser else { return false }
        do {
            let updatedCircle = try await repository.removeCircleMember(
                circleID: circle.id,
                ownerID: currentUser.id,
                memberID: memberID
            )
            self.circle = updatedCircle
            upsertCircle(updatedCircle)
            try await refreshTimeline(now: .now)
            scheduleWidgetSnapshotRefresh()
            message = "Member removed from \(updatedCircle.name)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func repeatBlessingCandidates(now: Date = .now) async -> [Blessing] {
        guard let circle, let currentUser else { return [] }
        let earliest = now.addingTimeInterval(-TimeInterval(circle.repeatWindowMinutes * 60))
        do {
            return try await repository.recentBlessings(
                authorID: currentUser.id,
                submittedAfter: earliest
            )
            .filter {
                RepeatBlessingPolicy.isEligible(
                    source: $0,
                    targetCircle: circle,
                    authorID: currentUser.id,
                    now: now
                )
            }
        } catch {
            message = error.localizedDescription
            return []
        }
    }

    func repeatBlessing(_ source: Blessing, now: Date = .now) async -> Bool {
        guard let prompt, let currentUser else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            submittedBlessing = try await repository.repeatBlessing(
                sourceBlessingID: source.id,
                targetPromptID: prompt.id,
                authorID: currentUser.id,
                now: now
            )
            try await refreshTimeline(now: now)
            message = "Your blessing was reused in this circle."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func leaveCurrentCircle() async -> Bool {
        guard let circle, let currentUser else { return false }
        do {
            try await repository.leaveCircle(circleID: circle.id, memberID: currentUser.id)
            let leftName = circle.name
            circles.removeAll { $0.id == circle.id }
            realtimeTask?.cancel()
            realtimeTask = nil
            self.circle = nil
            prompt = nil
            lanes = []
            submittedBlessing = nil
            if let nextCircle = circles.first {
                Self.persistedCircleID = nextCircle.id
                await switchCircle(to: nextCircle.id)
            } else {
                Self.persistedCircleID = nil
                selectedTab = 2
                scheduleWidgetSnapshotRefresh()
            }
            message = "You left \(leftName)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func bibleChapter(book: BibleBook, chapter: Int) async throws -> BibleChapter {
        try await bibleService.chapter(
            versionID: selectedBibleTranslation.id,
            book: book,
            chapter: chapter
        )
    }

    func scriptureText(for reference: ScriptureReference) async throws -> String {
        try await bibleService.passage(
            versionID: selectedBibleTranslation.id,
            reference: reference
        )
    }

    func responses(for blessing: Blessing) async -> [BlessingResponse] {
        guard let currentUser else { return [] }
        do {
            return try await repository.responses(blessingID: blessing.id, viewerID: currentUser.id)
        } catch {
            message = error.localizedDescription
            return []
        }
    }

    func canRespond(to blessing: Blessing, at date: Date = .now) -> Bool {
        ResponseCompositionPolicy.canRespond(
            to: blessing,
            currentPrompt: prompt,
            isCurrentPromptToday: isCurrentPromptToday(at: date)
        )
    }

    func submitResponse(
        to blessing: Blessing,
        mode: ResponseMode,
        body: String,
        audioURL: URL?
    ) async -> BlessingResponse? {
        guard let currentUser else { return nil }
        do {
            return try await repository.submitResponse(
                blessingID: blessing.id,
                circleID: blessing.circleID,
                authorID: currentUser.id,
                mode: mode,
                body: body,
                audioURL: audioURL,
                now: .now
            )
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "blessingcircle" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let circleValue = components?.queryItems?.first(where: { $0.name == "circle" })?.value,
           let circleID = UUID(uuidString: circleValue),
           circles.contains(where: { $0.id == circleID }) {
            await switchCircle(to: circleID)
        }

        switch url.host {
        case "today":
            selectedTab = 0
            if url.path == "/capture" { isCapturePresented = true }
        case "blessing":
            guard let blessingID = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)),
                  let item = blessingFeedItem(id: blessingID) else { return }
            selectedTab = 1
            deepLinkedBlessing = item
        default:
            return
        }
    }

    func receiveAPNSToken(_ token: String) {
        apnsToken = token
        Task { await syncDeviceRegistration() }
    }

#if DEBUG
    var supportsInteractiveDebugPrompt: Bool {
        repository is any DebugPromptProviding
    }

    func startDebugDailyBlessing(now: Date = .now) async {
        guard let circle else {
            message = "Choose a circle before starting a daily blessing test."
            return
        }
        isRunningDebugAction = true
        defer { isRunningDebugAction = false }

        do {
            let testPrompt: DailyPrompt
            if let debugRepository = repository as? any DebugPromptProviding {
                testPrompt = try await debugRepository.beginDebugPrompt(circleID: circle.id, now: now)
                isDebugPromptPreview = false
            } else {
                var circleCalendar = Calendar(identifier: .gregorian)
                circleCalendar.timeZone = TimeZone(identifier: circle.timeZoneIdentifier) ?? .current
                testPrompt = DailyPrompt(
                    id: UUID(),
                    circleID: circle.id,
                    localDate: circleCalendar.startOfDay(for: now),
                    startsAt: now,
                    endsAt: now.addingTimeInterval(circle.responseWindowDuration)
                )
                isDebugPromptPreview = true
            }

            await activityController.end()
            prompt = testPrompt
            submittedBlessing = nil
            isCapturePresented = false
            selectedTab = 0
            if !isDebugPromptPreview {
                try await refreshTimeline(now: now)
            }
            let activityResult = await activityController.startIfNeeded(
                prompt: testPrompt,
                circle: circle,
                requestsPushUpdates: false
            )
            let promptMessage = isDebugPromptPreview
                ? "Daily blessing preview started. Hosted submissions stay disabled because only the server can open a real prompt."
                : "Local daily blessing test started. The timer and capture flow are ready."
            message = "\(promptMessage) \(activityResult.debugMessage)"
        } catch {
            message = "Couldn’t start the daily blessing test: \(error.localizedDescription)"
        }
    }
#endif

    private func startLiveActivity(for prompt: DailyPrompt, circle: CircleGroup) async {
        let result = await activityController.startIfNeeded(
            prompt: prompt,
            circle: circle,
            requestsPushUpdates: usesAuthentication
        )
        if case let .failed(reason) = result {
            message = "The blessing window is open, but its Live Activity couldn’t start: \(reason)"
        }
    }

    private func startRealtimeUpdates() {
        realtimeTask?.cancel()
        guard let circle else { return }
        realtimeTask = Task { [weak self, repository] in
            do {
                let updates = try await repository.timelineUpdates(circleID: circle.id)
                for await _ in updates {
                    guard !Task.isCancelled else { break }
                    try await self?.refreshTimeline()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.message = "Live circle updates paused: \(error.localizedDescription)"
            }
        }
    }

    private func upsertCircle(_ circle: CircleGroup) {
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle.preservingInviteCode(circles[index].inviteCode)
        } else {
            circles.append(circle)
        }
    }

    private static let appearanceKey = "user.appearancePreference"
    private static let widgetRefreshKey = "user.widgetRefreshMinutes"
    static let widgetRefreshOptions = [15, 30, 60, 120, 240]

    private func blessingFeedItem(id: UUID) -> BlessingFeedItem? {
        for lane in lanes {
            for event in lane.events {
                if case let .blessing(blessing) = event.status, blessing.id == id {
                    return BlessingFeedItem(member: lane.member, blessing: blessing)
                }
            }
        }
        return nil
    }

    private func scheduleWidgetSnapshotRefresh(now: Date = .now) {
        widgetSnapshotTask?.cancel()
        widgetSnapshotTask = Task { [weak self] in
            await self?.writeWidgetSnapshot(now: now)
        }
    }

    private func writeWidgetSnapshot(now: Date) async {
        guard let currentUser else {
            BlessingWidgetSnapshotStore.save(.empty)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        struct Candidate {
            let circle: CircleGroup
            let member: Member
            let blessing: Blessing
            let isFromCurrentCircleDay: Bool
        }

        var promptSnapshots: [BlessingWidgetPrompt] = []
        var candidates: [Candidate] = []

        for membership in circles {
            guard !Task.isCancelled else { return }
            do {
                let context = try await repository.circleContext(circleID: membership.id)
                let circleLanes = try await repository.timeline(
                    circleID: membership.id,
                    viewerID: currentUser.id,
                    now: now
                )
                let currentPromptIsToday = context.prompt?.occursOnCircleDay(
                    at: now,
                    timeZoneIdentifier: context.circle.timeZoneIdentifier
                ) == true

                if let prompt = context.prompt, currentPromptIsToday {
                    let viewerHasSubmitted = circleLanes
                        .first(where: { $0.member.id == currentUser.id })?
                        .events
                        .contains(where: { event in
                            guard case let .blessing(blessing) = event.status else { return false }
                            return blessing.promptID == prompt.id
                        }) == true
                    promptSnapshots.append(
                        BlessingWidgetPrompt(
                            promptID: prompt.id,
                            circleID: context.circle.id,
                            circleName: context.circle.name,
                            startsAt: prompt.startsAt,
                            endsAt: prompt.endsAt,
                            viewerHasSubmitted: viewerHasSubmitted,
                            isOnCurrentCircleDay: true
                        )
                    )
                }

                for lane in circleLanes {
                    for event in lane.events {
                        guard case let .blessing(blessing) = event.status else { continue }
                        candidates.append(
                            Candidate(
                                circle: context.circle,
                                member: lane.member,
                                blessing: blessing,
                                isFromCurrentCircleDay: currentPromptIsToday
                                    && blessing.promptID == context.prompt?.id
                            )
                        )
                    }
                }
            } catch {
                continue
            }
        }

        var seenBlessingIDs = Set<UUID>()
        let uniqueCandidates = candidates
            .sorted { $0.blessing.submittedAt > $1.blessing.submittedAt }
            .filter { seenBlessingIDs.insert($0.blessing.id).inserted }
            .prefix(30)
        var blessingSnapshots: [BlessingWidgetBlessing] = []
        var referencesToLoad: [(UUID, ScriptureReference)] = []

        for (index, candidate) in uniqueCandidates.enumerated() {
            guard !Task.isCancelled else { return }
            let reference = candidate.blessing.scriptureReference
            if index < 8, let reference { referencesToLoad.append((candidate.blessing.id, reference)) }
            blessingSnapshots.append(
                BlessingWidgetBlessing(
                    id: candidate.blessing.id,
                    circleID: candidate.circle.id,
                    circleName: candidate.circle.name,
                    authorName: candidate.member.displayName,
                    captureMode: BlessingWidgetCaptureMode(rawValue: candidate.blessing.captureMode.rawValue) ?? .typed,
                    transcript: candidate.blessing.body ?? "",
                    submittedAt: candidate.blessing.submittedAt,
                    isFromCurrentCircleDay: candidate.isFromCurrentCircleDay,
                    scriptureReference: reference?.displayName,
                    scriptureText: nil,
                    bibleVersionName: reference == nil ? nil : selectedBibleTranslation.shortName
                )
            )
        }

        var snapshot = BlessingWidgetSnapshot(
            generatedAt: now,
            refreshIntervalMinutes: widgetRefreshMinutes,
            prompts: promptSnapshots,
            blessings: blessingSnapshots
        )
        BlessingWidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        let versionID = selectedBibleTranslation.id
        let loadedPassages = await withTaskGroup(of: (UUID, String?).self) { group in
            for (blessingID, reference) in referencesToLoad {
                group.addTask { [bibleService] in
                    let text = try? await bibleService.passage(versionID: versionID, reference: reference)
                    return (blessingID, text)
                }
            }
            var results: [UUID: String] = [:]
            for await (blessingID, text) in group {
                if let text { results[blessingID] = text }
            }
            return results
        }
        guard !Task.isCancelled, !loadedPassages.isEmpty else { return }
        for index in snapshot.blessings.indices {
            snapshot.blessings[index].scriptureText = loadedPassages[snapshot.blessings[index].id]
        }
        BlessingWidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func configureRemoteServices() async {
        guard usesAuthentication, !remoteServicesConfigured else { return }
        remoteServicesConfigured = true
        activityController.startMonitoringTokens(
            onPushToStartToken: { [weak self] token in
                await self?.receivePushToStartToken(token)
            },
            onActivityToken: { [weak self] promptID, activityID, token in
                await self?.registerActivity(promptID: promptID, activityID: activityID, token: token)
            }
        )
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            message = "Notifications are off. You can enable them later in Settings."
        }
    }

    private func receivePushToStartToken(_ token: String) async {
        pushToStartToken = token
        await syncDeviceRegistration()
    }

    private func syncDeviceRegistration() async {
        guard loadState == .ready else { return }
        do {
            try await repository.registerDevice(
                installationID: Self.installationID,
                apnsToken: apnsToken,
                pushToStartToken: pushToStartToken,
                environment: Self.pushEnvironment
            )
        } catch {
            message = "Push registration will retry next time the app opens."
        }
    }

    private func registerActivity(promptID: UUID, activityID: String, token: String) async {
        do {
            try await repository.registerActivity(
                promptID: promptID,
                activityID: activityID,
                pushToken: token,
                environment: Self.pushEnvironment
            )
        } catch {
            message = "Live Activity updates will retry next time the app opens."
        }
    }

    private static var installationID: UUID {
        let key = "blessingCircle.installationID"
        if let value = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    private static var persistedCircleID: UUID? {
        get {
            UserDefaults.standard.string(forKey: "blessingCircle.selectedCircleID")
                .flatMap(UUID.init(uuidString:))
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: "blessingCircle.selectedCircleID")
        }
    }

    private static var pushEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}
