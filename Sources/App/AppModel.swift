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
    private let savedBlessingStore: SavedBlessingStore
    private(set) var savedBlessings: [UUID: SavedBlessingRecord] = [:]
    private(set) var savingBlessingIDs: Set<UUID> = []
    private(set) var responseMediaDates: [UUID: [Date]] = [:]
    private var localSavingPreferences = LocalSavingPreferences()
    private var automaticSaveTask: Task<Void, Never>?
    private var automaticSaveRunID: UUID?
    private var automaticSaveNeedsAnotherPass = false
    private(set) var isChangingAutomaticSaving = false
    private(set) var isChoosingAutomaticSaving = false
    private(set) var automaticSavingError: String?
    private(set) var hasChosenInitialSaving = false
    var automaticallySavesLocally: Bool { localSavingPreferences.isEnabled }
    var automaticSavedBlessings: [SavedBlessingRecord] {
        savedBlessings.values.filter(\.isAutomatic).sorted { $0.blessing.submittedAt > $1.blessing.submittedAt }
    }
    private let activityController = PromptActivityController()
    private var realtimeTask: Task<Void, Never>?
    private var widgetSnapshotTask: Task<Void, Never>?
    private var remoteServicesConfigured = false
    private var apnsToken: String?
    private var pushToStartToken: String?
    private var pendingDeepLink: URL?

    var loadState: LoadState = .idle
    var currentUser: Member?
    var circles: [CircleGroup] = []
    var circle: CircleGroup?
    var prompt: DailyPrompt?
    var endOfDayPrompt: DailyPrompt?
    private(set) var capturePrompt: DailyPrompt?
    var lanes: [TimelineLane] = []
    var selectedTab = 0
    var isCapturePresented = false {
        didSet {
            if !isCapturePresented && !isSubmitting {
                capturePrompt = nil
            }
        }
    }
    var isPreparingCapture = false
    var isSubmitting = false
    private(set) var nudgingMembers: Set<NudgeKey> = []
    private(set) var nudgedMembers: Set<NudgeKey> = []
    var isSwitchingCircle = false
    var message: String?
    var submittedBlessing: Blessing?
    var deepLinkedBlessing: BlessingFeedItem?
    var isForcingCirclePrompt = false
    private(set) var pendingInviteCode: String? {
        didSet {
            if let pendingInviteCode {
                UserDefaults.standard.set(pendingInviteCode, forKey: Self.pendingInviteCodeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingInviteCodeKey)
            }
        }
    }
    var hasSeenAbout: Bool {
        didSet { UserDefaults.standard.set(hasSeenAbout, forKey: Self.hasSeenAboutKey) }
    }
    var hasChosenInitialAppearance: Bool {
        didSet { UserDefaults.standard.set(hasChosenInitialAppearance, forKey: Self.hasChosenAppearanceKey) }
    }
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
        authentication: (any AuthenticationProviding)? = nil,
        savedBlessingStore: SavedBlessingStore = SavedBlessingStore()
    ) {
        self.repository = repository
        self.bibleService = bibleService
        self.authentication = authentication
        self.savedBlessingStore = savedBlessingStore
        self.pendingInviteCode = UserDefaults.standard.string(forKey: Self.pendingInviteCodeKey)
            .flatMap(CircleInviteLink.normalize(code:))
        let skipsOnboarding = ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SKIP_ONBOARDING"] == "1"
        self.hasSeenAbout = skipsOnboarding || UserDefaults.standard.bool(forKey: Self.hasSeenAboutKey)
        self.hasChosenInitialAppearance = skipsOnboarding || UserDefaults.standard.bool(forKey: Self.hasChosenAppearanceKey)
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
        NotificationBrandPreference.save(self.appIconPreference.rawValue)
    }

    var hasSubmittedToday: Bool {
        currentUserBlessing() != nil
    }

    var hasSubmittedEndOfDay: Bool {
        guard let endOfDayPrompt else { return false }
        return currentUserBlessing(for: endOfDayPrompt) != nil
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
            NotificationBrandPreference.save(preference.rawValue)
        }
    }

    func isCurrentPromptToday(at date: Date = .now) -> Bool {
        guard let prompt, let circle else { return false }
        return prompt.occursOnCircleDay(at: date, timeZoneIdentifier: circle.timeZoneIdentifier)
    }

    func currentUserBlessing(at date: Date = .now) -> Blessing? {
        guard let currentUser, let prompt, isCurrentPromptToday(at: date) else { return nil }
        return currentUserBlessing(for: prompt, userID: currentUser.id)
    }

    func currentEndOfDayBlessing() -> Blessing? {
        guard let currentUser, let endOfDayPrompt else { return nil }
        return currentUserBlessing(for: endOfDayPrompt, userID: currentUser.id)
    }

    private func currentUserBlessing(for targetPrompt: DailyPrompt, userID: UUID? = nil) -> Blessing? {
        guard let userID = userID ?? currentUser?.id else { return nil }
        if let submittedBlessing, submittedBlessing.promptID == targetPrompt.id {
            return submittedBlessing
        }
        return lanes
            .first(where: { $0.member.id == userID })?
            .events
            .compactMap { event -> Blessing? in
                if case let .blessing(blessing) = event.status {
                    return blessing
                }
                return nil
            }
            .first(where: { $0.promptID == targetPrompt.id })
    }

    func currentPromptBlessings(at date: Date = .now) -> [BlessingFeedItem] {
        var visiblePromptIDs = Set<UUID>()
        if let prompt,
           isCurrentPromptToday(at: date),
           currentUserBlessing(at: date) != nil {
            visiblePromptIDs.insert(prompt.id)
        }
        if let endOfDayPrompt,
           endOfDayPrompt.occursOnCircleDay(
               at: date,
               timeZoneIdentifier: circle?.timeZoneIdentifier ?? TimeZone.current.identifier
           ) || isEndOfDayWindowOpen(at: date),
           currentUserBlessing(for: endOfDayPrompt) != nil {
            visiblePromptIDs.insert(endOfDayPrompt.id)
        }
        guard !visiblePromptIDs.isEmpty else { return [] }

        return lanes.flatMap { lane in
            lane.events.compactMap { event -> BlessingFeedItem? in
                guard case let .blessing(blessing) = event.status,
                      visiblePromptIDs.contains(blessing.promptID) else { return nil }
                return BlessingFeedItem(member: lane.member, blessing: blessing)
            }
        }
        .sorted { lhs, rhs in
            if lhs.blessing.submittedAt != rhs.blessing.submittedAt {
                return lhs.blessing.submittedAt > rhs.blessing.submittedAt
            }
            return lhs.member.displayName.localizedCaseInsensitiveCompare(rhs.member.displayName) == .orderedAscending
        }
    }

    func canEnterEndOfDayPrompt(at date: Date = .now) -> Bool {
        guard let endOfDayPrompt,
              currentUserBlessing(for: endOfDayPrompt) == nil else { return false }
        return isEndOfDayWindowOpen(at: date)
    }

    private func isEndOfDayWindowOpen(at date: Date) -> Bool {
        guard let endOfDayPrompt,
              endOfDayPrompt.phase(at: date) == .open else { return false }
        if let prompt,
           prompt.kind == .daily,
           prompt.startsAt > endOfDayPrompt.startsAt,
           prompt.startsAt <= date {
            return false
        }
        return true
    }

    func canEnterCurrentPrompt(at date: Date = .now) -> Bool {
#if DEBUG
        guard !isDebugPromptPreview else { return false }
#endif
        guard let prompt, let circle, isCurrentPromptToday(at: date), !hasSubmittedToday else { return false }
        if isFirstCircleDay(at: date) { return true }
        let phase = prompt.phase(at: date)
        return phase == .open || (phase == .closed && circle.allowsLateBlessings)
    }

    var canSubmitCurrentPrompt: Bool {
        canEnterCurrentPrompt()
    }

    func openCapture(for targetPrompt: DailyPrompt? = nil, now: Date = .now) async -> Bool {
        guard !isPreparingCapture, let targetPrompt = targetPrompt ?? prompt, let currentUser else {
            message = BlessingError.outsideResponseWindow.localizedDescription
            return false
        }
        isPreparingCapture = true
        defer { isPreparingCapture = false }
        do {
            try await repository.beginBlessingEntry(
                promptID: targetPrompt.id,
                memberID: currentUser.id,
                now: now
            )
            capturePrompt = targetPrompt
            isCapturePresented = true
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func isFirstCircleDay(at date: Date) -> Bool {
        guard let prompt, let circle, let userID = currentUser?.id,
              let membership = circle.members.first(where: { $0.id == userID }) else { return false }
        return FirstDaySubmissionPolicy.isEligible(
            memberJoinedAt: membership.joinedAt,
            prompt: prompt,
            circle: circle,
            now: date
        )
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
            if currentUser?.id != bootstrap.currentUser.id {
                nudgingMembers = []
                nudgedMembers = []
            }
            self.currentUser = bootstrap.currentUser
            savedBlessings = (try? await savedBlessingStore.load(userID: bootstrap.currentUser.id)) ?? [:]
            do {
                localSavingPreferences = try await savedBlessingStore.loadPreferences(userID: bootstrap.currentUser.id)
            } catch {
                // A damaged local preference must not block sign-in or circle access.
                localSavingPreferences = LocalSavingPreferences()
                automaticSavingError = "Local saving settings couldn’t be read. Please choose your preference again; existing saved copies are unchanged."
            }
            hasChosenInitialSaving = localSavingPreferences.hasChosen
                || ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SKIP_ONBOARDING"] == "1"
            self.circles = bootstrap.circles
            let preferredID = Self.persistedCircleID.flatMap { id in
                bootstrap.circles.contains(where: { $0.id == id }) ? id : nil
            } ?? bootstrap.selectedCircleID
            if let preferredID, preferredID != bootstrap.selectedCircleID {
                let context = try await repository.circleContext(circleID: preferredID)
                self.circle = context.circle
                self.prompt = context.prompt
                self.endOfDayPrompt = context.endOfDayPrompt
            } else {
                self.circle = bootstrap.circle
                self.prompt = bootstrap.prompt
                self.endOfDayPrompt = bootstrap.endOfDayPrompt
            }
            Self.persistedCircleID = self.circle?.id
            if self.circle == nil { selectedTab = 2 }
            try await refreshTimeline()
            loadState = .ready
            if pendingInviteCode != nil { selectedTab = 2 }
            startRealtimeUpdates()
            await configureRemoteServices()
            if let prompt = self.prompt,
               let circle = self.circle,
               prompt.phase(at: .now) == .open {
                await startLiveActivity(for: prompt, circle: circle)
            }
            await handlePendingDeepLinkIfNeeded()
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
            automaticSaveTask?.cancel()
            automaticSaveTask = nil
            automaticSaveRunID = nil
            currentUser = nil
            nudgingMembers = []
            nudgedMembers = []
            savedBlessings = [:]
            localSavingPreferences = LocalSavingPreferences()
            hasChosenInitialSaving = false
            automaticSavingError = nil
            isChoosingAutomaticSaving = false
            responseMediaDates = [:]
            circles = []
            circle = nil
            prompt = nil
            endOfDayPrompt = nil
            capturePrompt = nil
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
        scheduleAutomaticSaving()
    }

    func refreshCurrentCircle(now: Date = .now) async {
        do {
            try await reloadCurrentCircle(now: now)
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            message = "Couldn’t refresh your circle: \(error.localizedDescription)"
        }
    }

    func switchCircle(to circleID: UUID) async {
        guard !isSwitchingCircle,
              circle?.id != circleID,
              circles.contains(where: { $0.id == circleID }),
              let currentUser else { return }
        isSwitchingCircle = true
        defer { isSwitchingCircle = false }
        realtimeTask?.cancel()
        realtimeTask = nil
        do {
            let (context, targetLanes) = try await loadCircleSwitchData(
                circleID: circleID,
                viewerID: currentUser.id
            )
            let knownInviteCode = circles.first(where: { $0.id == circleID })?.inviteCode
            let resolvedCircle = context.circle.preservingInviteCode(knownInviteCode)
            circle = resolvedCircle
            prompt = context.prompt
            endOfDayPrompt = context.endOfDayPrompt
            capturePrompt = nil
#if DEBUG
            isDebugPromptPreview = false
#endif
            submittedBlessing = nil
            lanes = targetLanes
            if let index = circles.firstIndex(where: { $0.id == circleID }) {
                circles[index] = resolvedCircle
            }
            Self.persistedCircleID = circleID
            scheduleWidgetSnapshotRefresh()
            startRealtimeUpdates()
            if let prompt = context.prompt, prompt.phase(at: .now) == .open {
                await startLiveActivity(for: prompt, circle: resolvedCircle)
            }
        } catch {
            startRealtimeUpdates()
            guard !Task.isCancelled else { return }
            message = Self.isCancellation(error)
                ? "The circle switch was interrupted. Please try again."
                : "Couldn’t switch circles: \(error.localizedDescription)"
        }
    }

    private func loadCircleSwitchData(
        circleID: UUID,
        viewerID: UUID
    ) async throws -> (CircleContext, [TimelineLane]) {
        var lastCancellation: Error?
        for attempt in 0..<3 {
            do {
                let context = try await repository.circleContext(circleID: circleID)
                let lanes = try await repository.timeline(circleID: circleID, viewerID: viewerID, now: .now)
                return (context, lanes)
            } catch {
                guard Self.isCancellation(error), !Task.isCancelled else { throw error }
                lastCancellation = error
                guard attempt < 2 else { break }
                try await Task.sleep(for: .milliseconds(150 * (attempt + 1)))
            }
        }
        throw lastCancellation ?? CancellationError()
    }

    private func reloadCurrentCircle(now: Date) async throws {
        guard let selectedCircleID = circle?.id, let currentUser else { return }
        let context = try await repository.circleContext(circleID: selectedCircleID)
        let refreshedLanes = try await repository.timeline(
            circleID: selectedCircleID,
            viewerID: currentUser.id,
            now: now
        )
        guard circle?.id == selectedCircleID else { return }

        let knownInviteCode = circles.first(where: { $0.id == selectedCircleID })?.inviteCode
        let refreshedCircle = context.circle.preservingInviteCode(knownInviteCode)
        circle = refreshedCircle
        prompt = context.prompt
        endOfDayPrompt = context.endOfDayPrompt
        lanes = refreshedLanes
        upsertCircle(refreshedCircle)
        scheduleWidgetSnapshotRefresh(now: now)

        if let prompt = context.prompt, prompt.phase(at: now) == .open {
            await startLiveActivity(for: prompt, circle: refreshedCircle)
        }
    }

    private func activatePrompt(promptID: UUID, now: Date = .now) async -> Bool {
        guard !isSwitchingCircle, let currentUser else { return false }
        isSwitchingCircle = true
        defer { isSwitchingCircle = false }

        let previousCircleID = circle?.id
        var needsRealtimeRestart = false
        do {
            let context = try await repository.circleContext(promptID: promptID)
            guard circles.contains(where: { $0.id == context.circle.id }) else {
                throw BlessingError.circleNotFound
            }
            if previousCircleID != context.circle.id {
                realtimeTask?.cancel()
                realtimeTask = nil
                needsRealtimeRestart = true
            }
            let refreshedLanes = try await repository.timeline(
                circleID: context.circle.id,
                viewerID: currentUser.id,
                now: now
            )
            let knownInviteCode = circles.first(where: { $0.id == context.circle.id })?.inviteCode
            let resolvedCircle = context.circle.preservingInviteCode(knownInviteCode)
            circle = resolvedCircle
            prompt = context.prompt
            endOfDayPrompt = context.endOfDayPrompt
            let contextPromptIDs = Set([context.prompt?.id, context.endOfDayPrompt?.id].compactMap { $0 })
            if let activeCapturePrompt = capturePrompt,
               !contextPromptIDs.contains(activeCapturePrompt.id) {
                self.capturePrompt = nil
                submittedBlessing = nil
            }
            lanes = refreshedLanes
            upsertCircle(resolvedCircle)
            Self.persistedCircleID = resolvedCircle.id
            scheduleWidgetSnapshotRefresh(now: now)
            if previousCircleID != resolvedCircle.id {
                startRealtimeUpdates()
                needsRealtimeRestart = false
            }
            if let prompt = context.prompt, prompt.phase(at: now) == .open {
                await startLiveActivity(for: prompt, circle: resolvedCircle)
            }
            return true
        } catch {
            if needsRealtimeRestart {
                startRealtimeUpdates()
            }
            guard !Task.isCancelled, !Self.isCancellation(error) else { return false }
            message = error.localizedDescription
            return false
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let error = error as NSError
        let compactDescription = error.localizedDescription
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return error.domain == "Swift.CancellationError"
            || (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || compactDescription.contains("cancellationerror")
    }

    func submit(
        mode: CaptureMode,
        body: String?,
        audioURL: URL?,
        videoURL: URL?,
        photoURL: URL? = nil,
        scriptureReference: ScriptureReference?
    ) async -> Bool {
        guard let targetPrompt = capturePrompt ?? prompt, let currentUser else {
            message = BlessingError.outsideResponseWindow.localizedDescription
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let savedBlessing = try await repository.submit(
                promptID: targetPrompt.id,
                authorID: currentUser.id,
                mode: mode,
                body: body,
                audioURL: audioURL,
                videoURL: videoURL,
                photoURL: photoURL,
                scriptureReference: scriptureReference,
                now: .now
            )
            submittedBlessing = savedBlessing
            if targetPrompt.kind == .daily {
                let knownBlessingIDs = Set(
                    currentPromptBlessings(at: .now)
                        .map(\.blessing)
                        .filter { $0.promptID == targetPrompt.id }
                        .map(\.id) + [savedBlessing.id]
                )
                await activityController.markSubmitted(
                    promptID: targetPrompt.id,
                    responseCount: knownBlessingIDs.count
                )
            }
            do {
                try await refreshTimeline()
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return true }
                message = "Your blessing was shared. The timeline will refresh shortly."
                return true
            }
            message = "Your blessing was shared with the circle."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func canEdit(_ blessing: Blessing, at date: Date = .now) -> Bool {
        guard let currentUser else { return false }
        return BlessingEditPolicy.canEdit(blessing, authorID: currentUser.id, at: date)
    }

    func updateBlessing(
        _ blessing: Blessing,
        body: String,
        scriptureReference: ScriptureReference?
    ) async -> Blessing? {
        guard let currentUser else { return nil }
        do {
            let updated = try await repository.updateBlessing(
                blessingID: blessing.id,
                authorID: currentUser.id,
                body: body,
                scriptureReference: scriptureReference,
                now: .now
            )
            replaceBlessing(updated)
            message = "Your blessing was updated."
            return updated
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    private func replaceBlessing(_ updated: Blessing) {
        if submittedBlessing?.id == updated.id { submittedBlessing = updated }
        if deepLinkedBlessing?.blessing.id == updated.id,
           let member = deepLinkedBlessing?.member {
            deepLinkedBlessing = BlessingFeedItem(member: member, blessing: updated)
        }
        lanes = lanes.map { lane in
            let events = lane.events.map { event in
                guard case let .blessing(blessing) = event.status,
                      blessing.id == updated.id else { return event }
                return TimelineEvent(
                    memberID: lane.member.id,
                    date: event.date,
                    status: .blessing(updated),
                    promptKind: event.promptKind
                )
            }
            return TimelineLane(member: lane.member, events: events)
        }
        scheduleWidgetSnapshotRefresh()
    }

    func joinCircle(code: String) async -> Bool {
        guard let currentUser else { return false }
        guard let code = CircleInviteLink.normalize(code: code) else {
            message = "That circle invitation is not valid."
            return false
        }
        do {
            let joinedCircle = try await repository.joinCircle(code: code, memberID: currentUser.id)
            upsertCircle(joinedCircle)
            await switchCircle(to: joinedCircle.id)
            if pendingInviteCode == code { clearPendingInvite() }
            message = "You joined \(joinedCircle.name)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func createCircle(configuration: CircleConfiguration) async -> Bool {
        guard let currentUser else { return false }
        do {
            let createdCircle = try await repository.createCircle(
                configuration: configuration,
                member: currentUser
            )
            upsertCircle(createdCircle)
            await switchCircle(to: createdCircle.id)
            message = "Your new circle and today’s blessing time are ready."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func regenerateCurrentCircleInviteCode() async -> Bool {
        guard let circle, let currentUser else { return false }
        guard circle.ownerID == currentUser.id else {
            message = BlessingError.notCircleOwner.localizedDescription
            return false
        }
        do {
            let updatedCircle = try await repository.regenerateInviteCode(
                circleID: circle.id,
                ownerID: currentUser.id
            )
            self.circle = updatedCircle
            upsertCircle(updatedCircle)
            message = "A new circle code is ready. The previous code no longer works."
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
        repeatWindowMinutes: Int,
        endOfDayMinutes: Int
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
                repeatWindowMinutes: repeatWindowMinutes,
                endOfDayMinutes: endOfDayMinutes
            )
            self.circle = updatedCircle
            upsertCircle(updatedCircle)
            try await reloadCurrentCircle(now: .now)
            message = "Circle settings saved. The response length applies to future prompts."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func updateCirclePhoto(_ photoURL: URL?) async -> Bool {
        guard let circle, let currentUser else { return false }
        do {
            let updatedCircle = try await repository.updateCirclePhoto(
                circleID: circle.id,
                ownerID: currentUser.id,
                photoURL: photoURL
            )
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            scheduleWidgetSnapshotRefresh()
            message = photoURL == nil ? "Circle photo removed." : "Circle photo saved."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func setCircleActivityNotifications(_ enabled: Bool, for circleID: UUID) async {
        guard let currentUser,
              let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
        let previous = circles[index].circleActivityNotificationsEnabled
        circles[index].circleActivityNotificationsEnabled = enabled
        if circle?.id == circleID { circle?.circleActivityNotificationsEnabled = enabled }

        do {
            try await repository.updateCircleActivityNotifications(
                circleID: circleID,
                memberID: currentUser.id,
                enabled: enabled
            )
        } catch {
            circles[index].circleActivityNotificationsEnabled = previous
            if circle?.id == circleID { circle?.circleActivityNotificationsEnabled = previous }
            message = error.localizedDescription
        }
    }

    func setEndOfDayNotifications(_ enabled: Bool, for circleID: UUID) async {
        guard let currentUser,
              let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
        let previous = circles[index].endOfDayNotificationsEnabled
        circles[index].endOfDayNotificationsEnabled = enabled
        if circle?.id == circleID { circle?.endOfDayNotificationsEnabled = enabled }

        do {
            try await repository.updateEndOfDayNotifications(
                circleID: circleID,
                memberID: currentUser.id,
                enabled: enabled
            )
        } catch {
            circles[index].endOfDayNotificationsEnabled = previous
            if circle?.id == circleID { circle?.endOfDayNotificationsEnabled = previous }
            message = error.localizedDescription
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
            capturePrompt = nil
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

    func updateProfile(displayName: String, avatarURL: URL?) async -> Bool {
        guard let currentUser else { return false }
        do {
            let updated = try await repository.updateProfile(
                memberID: currentUser.id,
                displayName: displayName,
                avatarURL: avatarURL
            )
            self.currentUser = updated
            for index in circles.indices {
                if let memberIndex = circles[index].members.firstIndex(where: { $0.id == updated.id }) {
                    circles[index].members[memberIndex] = updatedWithJoinDate(updated, circles[index].members[memberIndex].joinedAt)
                }
            }
            if let circleID = circle?.id, let refreshed = circles.first(where: { $0.id == circleID }) {
                circle = refreshed
            }
            lanes = lanes.map { lane in
                guard lane.member.id == updated.id else { return lane }
                return TimelineLane(member: updatedWithJoinDate(updated, lane.member.joinedAt), events: lane.events)
            }
            scheduleWidgetSnapshotRefresh()
            message = "Profile saved."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func updatedWithJoinDate(_ member: Member, _ joinedAt: Date) -> Member {
        var updated = member
        updated.joinedAt = joinedAt
        return updated
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

    func nudgeCandidates(at date: Date = .now) -> [NudgeCandidate] {
        guard let circle, let user = currentUser else { return [] }
        return [prompt, endOfDayPrompt].compactMap { $0 }.flatMap { target in
            let shared = Set(lanes.flatMap(\.events).compactMap { event -> UUID? in
                if case let .blessing(blessing) = event.status, blessing.promptID == target.id {
                    return blessing.authorID
                }
                return nil
            })
            let next = prompt.flatMap { $0.kind == .daily && $0.startsAt > target.startsAt ? $0.startsAt : nil }
            return circle.members.filter { member in
                NudgePolicy.isEligible(prompt: target, circle: circle, senderID: user.id, recipientID: member.id,
                    senderHasShared: currentUserBlessing(for: target) != nil,
                    recipientHasShared: shared.contains(member.id), now: date, nextDailyStart: next)
            }.map { NudgeCandidate(prompt: target, member: $0) }
        }
    }

    func nudge(_ candidate: NudgeCandidate, now: Date = .now) async {
        guard let user = currentUser, !nudgingMembers.contains(candidate.id), !nudgedMembers.contains(candidate.id),
              nudgeCandidates(at: now).contains(where: { $0.id == candidate.id }) else { return }
        nudgingMembers.insert(candidate.id)
        defer { nudgingMembers.remove(candidate.id) }
        do {
            let queued = try await repository.nudgeMember(promptID: candidate.prompt.id,
                recipientID: candidate.member.id, senderID: user.id, now: now)
            guard currentUser?.id == user.id else { return }
            nudgedMembers.insert(candidate.id)
            message = queued
                ? "Nudge queued for \(candidate.member.displayName). Their notification settings still apply."
                : "This person has already been nudged for this blessing."
        } catch {
            guard currentUser?.id == user.id, !Self.isCancellation(error) else { return }
            message = error.localizedDescription
        }
    }

    func repeatBlessing(_ source: Blessing, now: Date = .now) async -> Bool {
        guard let targetPrompt = capturePrompt ?? prompt, let currentUser else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let savedBlessing = try await repository.repeatBlessing(
                sourceBlessingID: source.id,
                targetPromptID: targetPrompt.id,
                authorID: currentUser.id,
                now: now
            )
            submittedBlessing = savedBlessing
            if targetPrompt.kind == .daily {
                let knownBlessingIDs = Set(
                    currentPromptBlessings(at: now)
                        .map(\.blessing)
                        .filter { $0.promptID == targetPrompt.id }
                        .map(\.id) + [savedBlessing.id]
                )
                await activityController.markSubmitted(
                    promptID: targetPrompt.id,
                    responseCount: knownBlessingIDs.count
                )
            }
            do {
                try await refreshTimeline(now: now)
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return true }
                message = "Your blessing was reused. The timeline will refresh shortly."
                return true
            }
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
            endOfDayPrompt = nil
            capturePrompt = nil
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
            let responses = try await repository.responses(blessingID: blessing.id, viewerID: currentUser.id)
            responseMediaDates[blessing.id] = responses.filter { $0.mode == .voice }.map(\.submittedAt)
            if savedBlessings[blessing.id]?.isAutomatic == true { scheduleAutomaticSaving() }
            let saved = savedBlessings[blessing.id]?.responses ?? []
            return responses.map { response in
                if let localURL = saved.first(where: { $0.id == response.id })?.audioURL {
                    return response.replacingAudio(localURL)
                }
                return response.replacingAudio(
                    MediaRetentionPolicy.isExpired(submittedAt: response.submittedAt) ? nil : response.audioURL
                )
            }
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return [] }
            if let saved = savedBlessings[blessing.id] { return saved.responses }
            message = error.localizedDescription
            return []
        }
    }

    func resolvedBlessing(_ blessing: Blessing, at now: Date = .now) -> Blessing {
        let saved = savedBlessings[blessing.id]?.blessing
        let expired = MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt, at: now)
        return blessing.replacingMedia(
            audio: saved?.audioURL ?? (expired ? nil : blessing.audioURL),
            video: saved?.videoURL ?? (expired ? nil : blessing.videoURL),
            photo: saved?.photoURL ?? blessing.photoURL
        )
    }

    func mediaExpiryWarning(for blessing: Blessing, at now: Date = .now) -> String? {
        guard savedBlessings[blessing.id] == nil else { return nil }
        var dates = responseMediaDates[blessing.id] ?? []
        if blessing.captureMode != .typed { dates.append(blessing.submittedAt) }
        return dates.sorted().compactMap { MediaRetentionPolicy.warning(for: $0, at: now) }.first
    }

    func saveBlessing(_ blessing: Blessing) async -> Bool {
        guard let user = currentUser,
              circles.contains(where: { $0.id == blessing.circleID }),
              savedBlessings[blessing.id] == nil,
              !savingBlessingIDs.contains(blessing.id) else { return false }
        // Do not archive a fabricated or locked peer payload.
        guard lanes.flatMap(\.events).contains(where: {
            if case let .blessing(visible) = $0.status { return visible.id == blessing.id }
            return false
        }) else { return false }
        savingBlessingIDs.insert(blessing.id)
        defer { savingBlessingIDs.remove(blessing.id) }
        do {
            let responses = try await repository.responses(blessingID: blessing.id, viewerID: user.id)
            let available = resolvedBlessing(blessing)
            if blessing.captureMode != .typed,
               available.audioURL == nil && available.videoURL == nil,
               !MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt) {
                throw BlessingMediaSaveError.unavailable
            }
            let record = try await savedBlessingStore.save(
                blessing: available,
                responses: responses.map {
                    $0.replacingAudio(MediaRetentionPolicy.isExpired(submittedAt: $0.submittedAt) ? nil : $0.audioURL)
                }, userID: user.id
            )
            if currentUser?.id == user.id { savedBlessings[blessing.id] = record }
            return true
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return false }
            message = "Couldn’t save this blessing: \(error.localizedDescription)"
            return false
        }
    }

    func unsaveBlessing(_ blessing: Blessing) async {
        guard let userID = currentUser?.id else { return }
        do {
            var preferences = localSavingPreferences
            preferences.excludedBlessingIDs.insert(blessing.id)
            try await savedBlessingStore.savePreferences(preferences, userID: userID)
            guard currentUser?.id == userID else { return }
            localSavingPreferences = preferences
            try await savedBlessingStore.unsave(blessingID: blessing.id, userID: userID)
            if currentUser?.id == userID { savedBlessings.removeValue(forKey: blessing.id) }
        } catch {
            message = "Couldn’t remove the saved blessing: \(error.localizedDescription)"
        }
    }

    func setAutomaticSavingEnabled(_ enabled: Bool) async {
        guard let userID = currentUser?.id, !isChangingAutomaticSaving else { return }
        isChangingAutomaticSaving = true
        defer { isChangingAutomaticSaving = false }
        do {
            var preferences = localSavingPreferences
            preferences.isEnabled = enabled
            preferences.hasChosen = true
            try await savedBlessingStore.savePreferences(preferences, userID: userID)
            guard currentUser?.id == userID else { return }
            localSavingPreferences = preferences
            hasChosenInitialSaving = true
            automaticSavingError = nil
            isChangingAutomaticSaving = false
            if enabled { scheduleAutomaticSaving() }
        } catch { message = "Couldn’t change local saving: \(error.localizedDescription)" }
    }

    func pauseAutomaticSavingForSelection() async {
        isChoosingAutomaticSaving = true
        automaticSaveTask?.cancel()
        await automaticSaveTask?.value
        automaticSaveTask = nil
    }

    func resumeAutomaticSavingAfterSelection() {
        isChoosingAutomaticSaving = false
        scheduleAutomaticSaving()
    }

    func disableAutomaticSaving(keepingIDs: Set<UUID>) async -> Bool {
        guard let userID = currentUser?.id, !isChangingAutomaticSaving else { return false }
        isChangingAutomaticSaving = true
        defer { isChangingAutomaticSaving = false; isChoosingAutomaticSaving = false }
        automaticSaveTask?.cancel()
        await automaticSaveTask?.value
        automaticSaveTask = nil
        guard currentUser?.id == userID else { return false }
        do {
            var preferences = localSavingPreferences
            preferences.isEnabled = false
            preferences.hasChosen = true
            try await savedBlessingStore.savePreferences(preferences, userID: userID)
            localSavingPreferences = preferences
            hasChosenInitialSaving = true
            for record in automaticSavedBlessings {
                let id = record.blessing.id
                if keepingIDs.contains(id) {
                    let kept = try await savedBlessingStore.keepManually(blessingID: id, userID: userID)
                    guard currentUser?.id == userID else { return false }
                    savedBlessings[id] = kept
                } else {
                    try await savedBlessingStore.unsave(blessingID: id, userID: userID)
                    guard currentUser?.id == userID else { return false }
                    savedBlessings.removeValue(forKey: id)
                }
            }
            automaticSavingError = nil
            return true
        } catch {
            message = "Couldn’t finish changing saved copies: \(error.localizedDescription)"
            return false
        }
    }

    private func scheduleAutomaticSaving() {
        guard automaticallySavesLocally, !isChangingAutomaticSaving, !isChoosingAutomaticSaving else { return }
        if automaticSaveTask != nil {
            automaticSaveNeedsAnotherPass = true
            return
        }
        let runID = UUID()
        automaticSaveRunID = runID
        automaticSaveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.automaticSaveRunID == runID {
                    self.automaticSaveTask = nil
                    self.automaticSaveRunID = nil
                }
            }
            repeat {
                self.automaticSaveNeedsAnotherPass = false
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                await self.saveVisibleBlessingsAutomatically()
            } while self.automaticSaveNeedsAnotherPass && !Task.isCancelled && self.automaticallySavesLocally
        }
    }

    // Can also be awaited by local regression tests; production calls run away
    // from the main screen's loading lifecycle and never surface scrolling alerts.
    func saveVisibleBlessingsAutomatically() async {
        guard let userID = currentUser?.id, automaticallySavesLocally, !isChoosingAutomaticSaving else { return }
        let memberships = circles
        var failures = 0
        for membership in memberships {
            do {
                try Task.checkCancellation()
                let visibleLanes = membership.id == circle?.id ? lanes
                    : try await repository.timeline(circleID: membership.id, viewerID: userID, now: .now)
                let blessings = visibleLanes.flatMap(\.events).compactMap { event -> Blessing? in
                    if case let .blessing(blessing) = event.status { return blessing }
                    return nil
                }
                for blessing in blessings {
                    try Task.checkCancellation()
                    guard currentUser?.id == userID, automaticallySavesLocally,
                          circles.contains(where: { $0.id == blessing.circleID }) else { return }
                    guard !localSavingPreferences.excludedBlessingIDs.contains(blessing.id),
                          !savingBlessingIDs.contains(blessing.id) else { continue }
                    let existing = savedBlessings[blessing.id]
                    if let existing, !existing.isAutomatic { continue }
                    savingBlessingIDs.insert(blessing.id)
                    do {
                        defer { savingBlessingIDs.remove(blessing.id) }
                        let responses = try await repository.responses(blessingID: blessing.id, viewerID: userID)
                        if let existing,
                           existing.blessing.body == blessing.body,
                           existing.blessing.scriptureReference == blessing.scriptureReference,
                           existing.responses.map(\.id) == responses.map(\.id),
                           existing.responses.map(\.body) == responses.map(\.body) { continue }
                        let available = resolvedBlessing(blessing)
                        if blessing.captureMode != .typed, available.audioURL == nil && available.videoURL == nil,
                           !MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt) {
                            throw BlessingMediaSaveError.unavailable
                        }
                        let archivedResponses = responses.map { response in
                            response.replacingAudio(existing?.responses.first(where: { $0.id == response.id })?.audioURL
                                ?? (MediaRetentionPolicy.isExpired(submittedAt: response.submittedAt) ? nil : response.audioURL))
                        }
                        let record = try await savedBlessingStore.save(blessing: available, responses: archivedResponses,
                            userID: userID, automatically: true, refreshing: existing != nil)
                        guard currentUser?.id == userID, !Task.isCancelled else { return }
                        savedBlessings[blessing.id] = record
                    } catch {
                        if Task.isCancelled || Self.isCancellation(error) { return }
                        failures += 1
                    }
                }
            } catch {
                if Task.isCancelled || Self.isCancellation(error) { return }
                failures += 1
            }
        }
        if currentUser?.id == userID {
            automaticSavingError = failures == 0 ? nil
                : "Some blessings couldn’t be saved. Available copies will retry next time the app refreshes."
        }
    }

    func canRespond(to blessing: Blessing, at date: Date = .now) -> Bool {
        if let prompt,
           isCurrentPromptToday(at: date),
           blessing.promptID == prompt.id {
            return true
        }
        guard let endOfDayPrompt,
              blessing.promptID == endOfDayPrompt.id else { return false }
        return endOfDayPrompt.occursOnCircleDay(
            at: date,
            timeZoneIdentifier: circle?.timeZoneIdentifier ?? TimeZone.current.identifier
        ) || isEndOfDayWindowOpen(at: date)
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
        if let inviteCode = CircleInviteLink.code(from: url) {
            pendingInviteCode = inviteCode
            if loadState == .ready { selectedTab = 2 }
            return
        }
        guard url.scheme == "blessingcircle" else { return }
        guard loadState == .ready else {
            pendingDeepLink = url
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let promptID = components?.queryItems?
            .first(where: { $0.name == "prompt" })?
            .value
            .flatMap(UUID.init(uuidString:))
        if let promptID {
            guard await activatePrompt(promptID: promptID) else { return }
        } else if let circleValue = components?.queryItems?.first(where: { $0.name == "circle" })?.value,
           let circleID = UUID(uuidString: circleValue),
           circles.contains(where: { $0.id == circleID }) {
            if circle?.id == circleID {
                await refreshCurrentCircle()
            } else {
                await switchCircle(to: circleID)
            }
        } else {
            await refreshCurrentCircle()
        }

        switch url.host {
        case "today":
            selectedTab = 0
            if url.path == "/capture" {
                let targetPrompt = [prompt, endOfDayPrompt]
                    .compactMap { $0 }
                    .first { $0.id == promptID }
                _ = await openCapture(for: targetPrompt)
            }
        case "blessing":
            guard let blessingID = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)),
                  let item = blessingFeedItem(id: blessingID) else { return }
            selectedTab = 1
            deepLinkedBlessing = item
        default:
            return
        }
    }

    func handleForegroundNotification(_ url: URL?) async {
        guard loadState == .ready else { return }
        guard let url else {
            await refreshCurrentCircle()
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let circleValue = components?.queryItems?
            .first(where: { $0.name == "circle" })?
            .value
        let circleID = circleValue.flatMap { UUID(uuidString: $0) }
        if circleID == nil || circleID == circle?.id {
            let promptID = components?.queryItems?
                .first(where: { $0.name == "prompt" })?
                .value
                .flatMap(UUID.init(uuidString:))
            if let promptID {
                _ = await activatePrompt(promptID: promptID)
            } else {
                await refreshCurrentCircle()
            }
        }
    }

    private func handlePendingDeepLinkIfNeeded() async {
        guard let pendingDeepLink else { return }
        self.pendingDeepLink = nil
        await handleDeepLink(pendingDeepLink)
    }

    func clearPendingInvite() {
        pendingInviteCode = nil
    }

    func receiveAPNSToken(_ token: String) {
        apnsToken = token
        Task { await syncDeviceRegistration() }
    }

    func receiveAPNSRegistrationFailure(_ failure: String) {
        message = "This phone couldn’t register for notifications. Check that notifications are enabled, then reopen the app. \(failure)"
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
            capturePrompt = nil
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
                    try await self?.reloadCurrentCircle(now: .now)
                }
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
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
    private static let hasSeenAboutKey = "onboarding.hasSeenAbout"
    private static let hasChosenAppearanceKey = "onboarding.hasChosenAppearance"
    private static let widgetRefreshKey = "user.widgetRefreshMinutes"
    private static let pendingInviteCodeKey = "circle.pendingInviteCode"
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
            await syncDeviceRegistration()
        } catch {
            message = "Notifications are off. You can enable them later in Settings."
        }
    }

    private func receivePushToStartToken(_ token: String) async {
        pushToStartToken = token
        await syncDeviceRegistration()
    }

    private func syncDeviceRegistration() async {
        guard loadState == .ready, apnsToken != nil || pushToStartToken != nil else { return }
        var lastError: (any Error)?
        for retryDelay in [Duration.zero, .seconds(1), .seconds(3)] {
            do {
                if retryDelay > .zero { try await Task.sleep(for: retryDelay) }
                try Task.checkCancellation()
                try await repository.registerDevice(
                    installationID: Self.installationID,
                    apnsToken: apnsToken,
                    pushToStartToken: pushToStartToken,
                    environment: Self.pushEnvironment
                )
                if message?.hasPrefix("Push registration") == true { message = nil }
                return
            } catch is CancellationError {
                return
            } catch {
                lastError = error
            }
        }
        let detail = lastError?.localizedDescription ?? "The server did not respond."
        message = "Push registration couldn’t reach the server after three attempts. Reopen the app to retry. \(detail)"
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
