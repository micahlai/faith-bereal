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
    private let registersForRemoteNotifications: Bool
    private let runsBackgroundRefreshes: Bool
    let diagnosticCollection: DiagnosticCollectionController
    private let savedBlessingStore: SavedBlessingStore
    private let draftStore: BlessingDraftStore
    private let metadataStore: CircleMetadataStore
    private let networkSavingPolicy: any NetworkSavingChecking
    private(set) var automaticSavingWaitingForWiFi = false
    var automaticallySavesOnWiFiOnly: Bool { localSavingPreferences.wifiOnly ?? true }
    var automaticallySavesOlderHistory: Bool { localSavingPreferences.includesOlderHistory ?? false }
    private var automaticHistoryCursors: [UUID: Date] = [:]
    private var automaticHistoryCompleted: Set<UUID> = []
    private var lastVisibleReadAt: Date?
    private struct BackgroundRead {
        let context: CircleContext
        let page: TimelinePage
        let date: Date
    }
    private var backgroundReads: [UUID: BackgroundRead] = [:]
    private var backgroundReadTasks: [UUID: Task<BackgroundRead, Error>] = [:]
    private var lastWidgetWriteAt: Date?
    private var lastWidgetRevision: UUID?
    private var metadataSaveTask: Task<Void, Never>?
    private(set) var isShowingCachedMetadata = false
    private(set) var isPageLoading = false
    private(set) var pageLoadError: String?
    var canUseFreshCircle: Bool { !isShowingCachedMetadata && !isShowingSavedTimeline && !isSwitchingCircle }
    private(set) var savedDrafts: [BlessingDraft] = []
    private(set) var captureDraftToRestore: BlessingDraft?
    private(set) var draftSaveError: String?
    private(set) var savedBlessings: [UUID: SavedBlessingRecord] = [:]
    private(set) var savedArchiveAccountID: UUID?
    private(set) var isShowingSavedTimeline = false
    var savedArchiveRecords: [SavedBlessingRecord] {
        savedBlessings.values.sorted { $0.blessing.submittedAt > $1.blessing.submittedAt }
    }
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
    private var streakRefreshTask: Task<Void, Never>?
    private(set) var nextStreakRefreshAt: Date?
    private var widgetSnapshotTask: Task<Void, Never>?
    private var widgetSnapshotPendingDate: Date?
    private var remoteServicesConfigured = false
    private var apnsToken: String?
    private var pushToStartToken: String?
    private var pendingDeepLink: URL?

    var loadState: LoadState = .idle
    private var dataScopeGeneration = UUID() {
        didSet {
            invalidateTimelineResponders()
            backgroundReadTasks.values.forEach { $0.cancel() }
            backgroundReadTasks = [:]; backgroundReads = [:]
            lastVisibleReadAt = nil; lastWidgetWriteAt = nil
            automaticHistoryCursors = [:]; automaticHistoryCompleted = []
        }
    }
    private var timelineResponderCache = TimelineResponderSummaryCache()
    private(set) var timelineResponderRevision = UUID()
    private var timelineRefreshGeneration: UUID?
    private var bootstrapGeneration = UUID()
    private var pageLoadGeneration = UUID()
    var currentUser: Member? {
        didSet {
            if currentUser?.id != oldValue?.id {
                if let accountID = currentUser?.id, let archiveID = savedArchiveAccountID, accountID != archiveID {
                    savedBlessings = [:]
                    savedArchiveAccountID = nil
                    isShowingSavedTimeline = false
                }
                streakRefreshTask?.cancel()
                streakRefreshTask = nil
                nextStreakRefreshAt = nil
                dataScopeGeneration = UUID()
                if oldValue != nil { diagnosticCollection.deactivate() }
                if let previousID = oldValue?.id {
                    Task {
                        await IdentityPhotoCache.shared.clear(accountID: previousID)
                        await MediaDownloadCache.shared.clear(accountID: previousID)
                    }
                }
            }
        }
    }
    var circles: [CircleGroup] = []
    var circle: CircleGroup? {
        didSet {
            if circle?.id != oldValue?.id || circle?.timeZoneIdentifier != oldValue?.timeZoneIdentifier {
                streakRefreshTask?.cancel()
                streakRefreshTask = nil
                nextStreakRefreshAt = nil
                dataScopeGeneration = UUID()
            }
        }
    }
    var prompt: DailyPrompt?
    var endOfDayPrompt: DailyPrompt?
    private(set) var capturePrompt: DailyPrompt?
    var lanes: [TimelineLane] = [] {
        didSet {
            timelineVisibleBlessingIDs = Set(lanes.flatMap(\.events).compactMap { event in
                if case let .blessing(blessing) = event.status { return blessing.id }
                return nil
            })
        }
    }
    private var timelineVisibleBlessingIDs: Set<UUID> = []
    private(set) var timelineNextBeforeDate: Date?
    private(set) var isLoadingMoreTimeline = false
    private(set) var timelineLoadError: String?
    private var timelinePagingScope: String?
    private var timelineHasLoadedMore = false
    var selectedTab = 0
    var isCapturePresented = false {
        didSet {
            if !isCapturePresented && !isSubmitting {
                capturePrompt = nil
                captureDraftToRestore = nil
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
        savedBlessingStore: SavedBlessingStore = SavedBlessingStore(),
        draftStore: BlessingDraftStore = BlessingDraftStore(),
        diagnosticCollection: DiagnosticCollectionController = DiagnosticCollectionController(),
        metadataStore: CircleMetadataStore = .shared,
        registersForRemoteNotifications: Bool = true,
        runsBackgroundRefreshes: Bool = true,
        networkSavingPolicy: any NetworkSavingChecking = NetworkSavingPolicy.shared
    ) {
        self.repository = repository
        self.bibleService = bibleService
        self.authentication = authentication
        self.registersForRemoteNotifications = registersForRemoteNotifications
        self.runsBackgroundRefreshes = runsBackgroundRefreshes
        self.diagnosticCollection = diagnosticCollection
        self.savedBlessingStore = savedBlessingStore
        self.draftStore = draftStore
        self.metadataStore = metadataStore
        self.networkSavingPolicy = networkSavingPolicy
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
            || (prompt.firstJoinEndsAt != nil && isFirstCircleDay(at: date))
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
        guard canUseFreshCircle else { return false }
        guard let endOfDayPrompt,
              currentUserBlessing(for: endOfDayPrompt) == nil else { return false }
        return isEndOfDayWindowOpen(at: date)
    }

    private func isEndOfDayWindowOpen(at date: Date) -> Bool {
        guard let endOfDayPrompt,
              endOfDayPrompt.phase(at: date) == .open else { return false }
        if let prompt,
           prompt.kind == .daily,
           prompt.notificationHasStarted != false,
           prompt.startsAt > endOfDayPrompt.startsAt,
           prompt.startsAt <= date {
            return false
        }
        return true
    }

    func canEnterCurrentPrompt(at date: Date = .now) -> Bool {
        guard canUseFreshCircle else { return false }
#if DEBUG
        guard !isDebugPromptPreview else { return false }
#endif
        guard let prompt, let circle, isCurrentPromptToday(at: date), !hasSubmittedToday else { return false }
        if let member = circle.members.first(where: { $0.id == currentUser?.id }),
           FirstDaySubmissionPolicy.isEligible(memberJoinedAt: member.joinedAt, prompt: prompt, circle: circle, now: date) {
            return true
        }
        let phase = prompt.phase(at: date)
        return phase == .open || (phase == .closed && circle.allowsLateBlessings
            && prompt.occursOnCircleDay(at: date, timeZoneIdentifier: circle.timeZoneIdentifier))
    }

    var canSubmitCurrentPrompt: Bool {
        canEnterCurrentPrompt()
    }

    func openCapture(for targetPrompt: DailyPrompt? = nil, now: Date = .now) async -> Bool {
        guard !isPreparingCapture, canUseFreshCircle,
              let targetPrompt = targetPrompt ?? prompt, let currentUser,
              circle?.id == targetPrompt.circleID else {
            message = BlessingError.outsideResponseWindow.localizedDescription
            return false
        }
        isPreparingCapture = true
        defer { isPreparingCapture = false }
        let generation = dataScopeGeneration
        do {
            try await repository.beginBlessingEntry(
                promptID: targetPrompt.id,
                memberID: currentUser.id,
                now: now
            )
            guard !Task.isCancelled, dataScopeGeneration == generation else { return false }
            await draftStore.beginEditing(authorID: currentUser.id, circleID: targetPrompt.circleID, promptID: targetPrompt.id)
            guard !Task.isCancelled, dataScopeGeneration == generation else { return false }
            capturePrompt = targetPrompt
            captureDraftToRestore = resumableDraft(for: targetPrompt, at: now)
            isCapturePresented = true
            return true
        } catch {
            guard dataScopeGeneration == generation, !Task.isCancelled else { return false }
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
        let startup = UUID()
        bootstrapGeneration = startup
        pageLoadGeneration = startup
        isPageLoading = true
        pageLoadError = nil
        defer { if pageLoadGeneration == startup { isPageLoading = false } }
        var span: BackendDiagnostics.Span?
        var measuredReady = false
        defer { if !measuredReady { span?.finish(Task.isCancelled ? .cancelled : .failure) } }
        loadState = .loading
        if let accountID = await authentication?.cachedUserID() {
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            await restoreSavedArchive(accountID: accountID, startup: startup)
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            if let cached = await metadataStore.load(accountID: accountID) {
                guard bootstrapGeneration == startup, !Task.isCancelled else { return }
                currentUser = cached.currentUser
                circles = cached.circles
                let selected = Self.persistedCircleID ?? cached.selectedCircleID
                circle = cached.circles.first { $0.id == selected } ?? cached.circles.first
                prompt = nil; endOfDayPrompt = nil; lanes = []
                if !savedBlessings.isEmpty { showSavedTimeline() }
                isShowingCachedMetadata = true
                if let preferences = try? await savedBlessingStore.loadPreferences(userID: accountID) {
                    guard bootstrapGeneration == startup, !Task.isCancelled else { return }
                    localSavingPreferences = preferences
                    hasChosenInitialSaving = preferences.hasChosen
                        || ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SKIP_ONBOARDING"] == "1"
                }
                guard bootstrapGeneration == startup, !Task.isCancelled else { return }
                loadState = .ready
            }
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            // Present local identity before opening the diagnostic queue. Capture
            // still starts before session validation, including a failed refresh.
            await diagnosticCollection.activate(accountID: accountID)
        } else if authentication != nil {
            savedBlessings = [:]
            savedArchiveAccountID = nil
            isShowingSavedTimeline = false
        }
        // Cached identity restores collection before a session refresh can fail.
        // It never grants content access; the repository still authorizes every read.
        span = BackendDiagnostics.shared.begin(.bootstrapVisible)
        let hasSession = await authentication?.hasSession() ?? true
        guard bootstrapGeneration == startup, !Task.isCancelled else { return }
        if !hasSession {
            if let userID = currentUser?.id { await metadataStore.remove(accountID: userID) }
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            if savedBlessings.isEmpty { clearCachedPresentation() }
            else { showSavedTimeline() }
            loadState = isShowingSavedTimeline ? .ready : .signedOut
            if isShowingSavedTimeline { pageLoadError = "You’re offline. Showing your saved blessings." }
            savedDrafts = []
            captureDraftToRestore = nil
            draftSaveError = nil
            return
        }
        if let accountID = await authentication?.currentUserID() {
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            if savedArchiveAccountID != accountID {
                await restoreSavedArchive(accountID: accountID, startup: startup)
                guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            }
            await diagnosticCollection.activate(accountID: accountID)
        }
        guard bootstrapGeneration == startup, !Task.isCancelled else { return }
        do {
            let bootstrap = try await repository.bootstrap()
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
#if DEBUG
            // Explicit local-only UI fixture: hold the real metadata-only loading
            // presentation while automation inspects navigation and access gates.
            if authentication == nil, ProcessInfo.processInfo.arguments.contains("--manna-loading-ui-test") {
                currentUser = bootstrap.currentUser; circles = bootstrap.circles; circle = bootstrap.circle
                prompt = nil; endOfDayPrompt = nil; lanes = []
                hasSeenAbout = true; hasChosenInitialAppearance = true; hasChosenInitialSaving = true
                isShowingCachedMetadata = true; loadState = .ready
                try await Task.sleep(for: .seconds(300))
                try Task.checkCancellation()
            }
#endif
            if currentUser?.id != bootstrap.currentUser.id {
                nudgingMembers = []
                nudgedMembers = []
            }
            self.currentUser = bootstrap.currentUser
            let accountGeneration = dataScopeGeneration
            await diagnosticCollection.activate(accountID: bootstrap.currentUser.id)
            let loadedBlessings = (try? await savedBlessingStore.load(userID: bootstrap.currentUser.id)) ?? [:]
            guard bootstrapGeneration == startup, dataScopeGeneration == accountGeneration, !Task.isCancelled else { return }
            savedBlessings = loadedBlessings
            savedArchiveAccountID = bootstrap.currentUser.id
            do {
                let preferences = try await savedBlessingStore.loadPreferences(userID: bootstrap.currentUser.id)
                guard bootstrapGeneration == startup, dataScopeGeneration == accountGeneration, !Task.isCancelled else { return }
                localSavingPreferences = preferences
            } catch {
                guard bootstrapGeneration == startup, dataScopeGeneration == accountGeneration, !Task.isCancelled else { return }
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
                guard bootstrapGeneration == startup, dataScopeGeneration == accountGeneration, !Task.isCancelled else { return }
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
            let metadataGeneration = dataScopeGeneration
            if let selected = self.circle,
               let index = self.circles.firstIndex(where: { $0.id == selected.id }) {
                self.circles[index] = selected
            }
            // Fresh identity is useful even if blessing reads or media signing
            // stall. Keep all content actions gated until the page is authorized.
            isShowingCachedMetadata = true
            loadState = .ready
            if authentication != nil {
                await metadataStore.save(accountID: bootstrap.currentUser.id,
                    currentUser: bootstrap.currentUser, circles: self.circles,
                    selectedCircleID: self.circle?.id)
                guard bootstrapGeneration == startup, dataScopeGeneration == metadataGeneration,
                      !Task.isCancelled else { return }
            }
            try await refreshTimeline(freshCircle: self.circle)
            guard bootstrapGeneration == startup, !Task.isCancelled,
                  currentUser?.id == bootstrap.currentUser.id else { return }
            isShowingCachedMetadata = false
            isShowingSavedTimeline = false
            await persistMetadata()
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            loadState = .ready
            span?.finish(.success)
            measuredReady = true
            if pendingInviteCode != nil { selectedTab = 2 }
            startRealtimeUpdates()
            await configureRemoteServices()
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            if let prompt = self.prompt,
               let circle = self.circle,
               prompt.phase(at: .now) == .open {
                await startLiveActivity(for: prompt, circle: circle)
            }
            await handlePendingDeepLinkIfNeeded()
        } catch {
            guard bootstrapGeneration == startup, !Task.isCancelled else { return }
            if isShowingCachedMetadata || isShowingSavedTimeline {
                if !savedBlessings.isEmpty { showSavedTimeline() }
                // Saved copies remain read-only while fresh content is unavailable.
                pageLoadError = "Couldn’t load your circle: \(error.localizedDescription)"
                loadState = .ready
            } else {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    private func restoreSavedArchive(accountID: UUID, startup: UUID) async {
        if savedArchiveAccountID != accountID {
            savedBlessings = [:]
            savedArchiveAccountID = nil
            isShowingSavedTimeline = false
        }
        let scope = dataScopeGeneration
        let records = (try? await savedBlessingStore.load(userID: accountID)) ?? [:]
        guard bootstrapGeneration == startup, dataScopeGeneration == scope, !Task.isCancelled else { return }
        savedBlessings = records
        savedArchiveAccountID = accountID
        if !records.isEmpty { showSavedTimeline() }
    }

    // These are private completed saves, not cached server permissions. No
    // prompts or membership privileges are inferred from an archive.
    private func showSavedTimeline() {
        guard let accountID = savedArchiveAccountID, !savedBlessings.isEmpty else { return }
        let firstPresentation = !isShowingSavedTimeline
        isShowingSavedTimeline = true
        isShowingCachedMetadata = true
        currentUser = currentUser?.id == accountID ? currentUser :
            Member(id: accountID, displayName: "You", initials: "Y", tintSeed: 0)
        let knownCircles = circles
        let ids = Set(savedBlessings.values.map { $0.blessing.circleID })
        circles = ids.sorted { $0.uuidString < $1.uuidString }.map { id in
            var value = knownCircles.first { $0.id == id } ?? CircleGroup(id: id,
                name: "Saved circle", inviteCode: "", ownerID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                members: [], timeZoneIdentifier: "UTC", randomWindowStartMinutes: 0,
                randomWindowEndMinutes: 0, responseWindowMinutes: 10, allowsLateBlessings: false,
                repeatWindowMinutes: 0)
            let authors = Set(savedBlessings.values.filter { $0.blessing.circleID == id }.map { $0.blessing.authorID })
            value.members = authors.sorted { $0.uuidString < $1.uuidString }.map { author in
                var member = value.members.first { $0.id == author } ?? Member(id: author,
                    displayName: author == accountID ? "You" : "Circle member", initials: author == accountID ? "Y" : "M", tintSeed: 0)
                member.avatarURL = member.avatarURL?.isFileURL == true ? member.avatarURL : nil
                return member
            }
            value.photoURL = nil
            value.inviteCode = ""
            value.allowMemberCircleChanges = false
            return value
        }
        let selectedID = circle?.id ?? Self.persistedCircleID
        circle = circles.first { $0.id == selectedID } ?? circles.first
        prompt = nil; endOfDayPrompt = nil
        lanes = savedTimelineLanes(circleID: circle?.id, now: .now)
        loadState = .ready
        if firstPresentation { selectedTab = 1 }
    }

    private func savedTimelineLanes(circleID: UUID?, now: Date) -> [TimelineLane] {
        guard let circleID, let accountID = savedArchiveAccountID else { return [] }
        let records = savedBlessings.values.filter { $0.blessing.circleID == circleID }
        let ownPrompts = Set(records.filter { $0.blessing.authorID == accountID }.map { $0.blessing.promptID })
        // Old manifests have no prompt date/time zone. A conservative 26-hour
        // boundary avoids exposing a today's peer save without our own post.
        let visible = records.filter { $0.blessing.authorID == accountID ||
            ownPrompts.contains($0.blessing.promptID) || now.timeIntervalSince($0.blessing.submittedAt) > 26 * 3600 }
        return Dictionary(grouping: visible, by: { $0.blessing.authorID }).map { author, records in
            let member = circle?.members.first { $0.id == author } ?? Member(id: author,
                displayName: author == accountID ? "You" : "Circle member", initials: author == accountID ? "Y" : "M", tintSeed: 0)
            return TimelineLane(member: member, events: records.map { record in
                TimelineEvent(memberID: author, date: record.blessing.submittedAt,
                    status: .blessing(record.blessing), id: "saved-\(record.blessing.id)")
            }.sorted { $0.date > $1.date })
        }.sorted { $0.member.id.uuidString < $1.member.id.uuidString }
    }

    private func mergeSavedHistory(now: Date) {
        guard let circleID = circle?.id else { return }
        let serverIDs = Set(lanes.flatMap(\.events).compactMap { event -> UUID? in
            if case let .blessing(value) = event.status, !event.id.hasPrefix("saved-") { return value.id }
            return nil
        })
        var combined = lanes.map { lane in
            TimelineLane(member: lane.member, events: lane.events.filter { event in
                if case let .blessing(value) = event.status, event.id.hasPrefix("saved-") {
                    return !serverIDs.contains(value.id)
                }
                return true
            })
        }
        let existingIDs = Set(combined.flatMap(\.events).compactMap { event -> UUID? in
            if case let .blessing(value) = event.status { return value.id }; return nil
        })
        for saved in savedTimelineLanes(circleID: circleID, now: now) {
            let events = saved.events.filter { event in
                guard case let .blessing(value) = event.status else { return false }
                return !existingIDs.contains(value.id) && now.timeIntervalSince(value.submittedAt) > 26 * 3600
            }
            guard !events.isEmpty else { continue }
            if let index = combined.firstIndex(where: { $0.id == saved.id }) {
                combined[index] = TimelineLane(member: combined[index].member,
                    events: (combined[index].events + events).sorted { $0.date > $1.date })
            } else { combined.append(TimelineLane(member: saved.member, events: events)) }
        }
        lanes = combined
    }

    func retryPageLoad() async {
        guard !isPageLoading, !isSwitchingCircle else { return }
        if isShowingCachedMetadata || isShowingSavedTimeline || loadState != .ready {
            loadState = .idle
            await bootstrap()
        } else { await refreshCurrentCircle() }
    }

    private func clearCachedPresentation() {
        currentUser = nil; circles = []; circle = nil
        prompt = nil; endOfDayPrompt = nil; lanes = []
        isShowingCachedMetadata = false
    }

    private func persistMetadata() async {
        guard authentication != nil, !isShowingCachedMetadata, let currentUser else { return }
        await metadataStore.save(accountID: currentUser.id, currentUser: currentUser,
            circles: circles, selectedCircleID: circle?.id)
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async {
        guard let authentication else { return }
        diagnosticCollection.deactivate()
        savedBlessings = [:]
        savedArchiveAccountID = nil
        isShowingSavedTimeline = false
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
        streakRefreshTask?.cancel()
        streakRefreshTask = nil
        nextStreakRefreshAt = nil
        bootstrapGeneration = UUID()
        pageLoadGeneration = UUID()
        isPageLoading = false
        isSwitchingCircle = false
        let previousUserID = currentUser?.id ?? savedArchiveAccountID
        diagnosticCollection.deactivate()
        do {
            try await authentication.signOut()
            metadataSaveTask?.cancel()
            await metadataSaveTask?.value
            if let previousUserID {
                await metadataStore.remove(accountID: previousUserID)
                await IdentityPhotoCache.shared.clear(accountID: previousUserID)
            }
            isShowingCachedMetadata = false; pageLoadError = nil
            automaticSaveTask?.cancel()
            automaticSaveTask = nil
            automaticSaveRunID = nil
            currentUser = nil
            nudgingMembers = []
            nudgedMembers = []
            savedBlessings = [:]
            savedArchiveAccountID = nil
            isShowingSavedTimeline = false
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
            if let accountID = currentUser?.id { await diagnosticCollection.activate(accountID: accountID) }
            message = error.localizedDescription
        }
    }

    func refreshTimeline(now: Date = .now, freshCircle: CircleGroup? = nil) async throws {
        guard let circle, let currentUser else { return }
        if freshCircle == nil {
            guard canUseFreshCircle, !isPageLoading else { return }
        }
        let generation = dataScopeGeneration
        guard timelineRefreshGeneration != generation else { return }
        timelineRefreshGeneration = generation
        defer { if timelineRefreshGeneration == generation { timelineRefreshGeneration = nil } }
        let span = BackendDiagnostics.shared.begin(.timelineRefresh)
        var outcome = BackendOutcome.failure
        defer { span.finish(Task.isCancelled ? .cancelled : outcome) }
        let page: TimelinePage
        if let freshCircle, freshCircle.id == circle.id {
            page = try await repository.timelinePage(circle: freshCircle, viewerID: currentUser.id, now: now, before: nil)
        } else {
            page = try await repository.timelinePage(circleID: circle.id, viewerID: currentUser.id, now: now, before: nil)
        }
        guard !Task.isCancelled, dataScopeGeneration == generation,
              self.circle?.id == circle.id, self.currentUser?.id == currentUser.id else { return }
        installTimelinePage(page, circleID: circle.id, reset: isShowingSavedTimeline)
        await reloadDrafts(now: now)
        scheduleWidgetSnapshotRefresh(now: now)
        scheduleAutomaticSaving()
        outcome = .success
    }

    func reloadDrafts(now: Date = .now) async {
        guard let userID = currentUser?.id else { savedDrafts = []; return }
        do {
            let loaded = try await draftStore.load(authorID: userID, now: now)
            guard currentUser?.id == userID else { return }
            let sent = Set(lanes.flatMap(\.events).compactMap { event -> UUID? in
                if case let .blessing(blessing) = event.status, blessing.authorID == userID { return blessing.promptID }
                return nil
            })
            for draft in loaded where sent.contains(draft.promptID) {
                try? await draftStore.markSent(authorID: userID, circleID: draft.circleID, promptID: draft.promptID)
            }
            savedDrafts = loaded.filter { !sent.contains($0.promptID) }
        } catch { draftSaveError = "Local drafts couldn’t be read. Your current composer is unchanged." }
    }

    func resumableDrafts(at now: Date) -> [BlessingDraft] {
        guard let circle, let userID = currentUser?.id else { return [] }
        return savedDrafts.filter { draft in
            guard let target = [prompt, endOfDayPrompt].compactMap({ $0 }).first(where: { $0.id == draft.promptID }),
                  currentUserBlessing(for: target) == nil else { return false }
            return BlessingDraftPolicy.canResume(draft, authorID: userID, prompt: target, circle: circle,
                now: now, nextDailyPrompt: prompt)
        }
    }

    func resumableDraft(for target: DailyPrompt, at now: Date) -> BlessingDraft? {
        resumableDrafts(at: now).first { $0.promptID == target.id && $0.circleID == target.circleID }
    }

    func persistDraft(_ draft: BlessingDraft) async -> Bool {
        guard currentUser?.id == draft.authorID else { return false }
        do {
            let saved = try await draftStore.save(draft)
            guard currentUser?.id == draft.authorID else { return false }
            guard !Task.isCancelled else { return true }
            savedDrafts.removeAll { $0.promptID == draft.promptID && $0.circleID == draft.circleID }
            if let saved { savedDrafts.append(saved) }
            draftSaveError = nil
            return true
        } catch {
            draftSaveError = "Couldn’t save this draft on your device. Free some storage and try again before sending."
            return false
        }
    }

    func prepareDraftForEditing(_ draft: BlessingDraft) async throws -> BlessingDraft {
        guard currentUser?.id == draft.authorID else { throw BlessingMediaSaveError.unavailable }
        return try await draftStore.copyForEditing(draft)
    }

    private func clearSentDraft(promptID: UUID, circleID: UUID, authorID: UUID) async {
        try? await draftStore.markSent(authorID: authorID, circleID: circleID, promptID: promptID)
        guard currentUser?.id == authorID else { return }
        savedDrafts.removeAll { $0.promptID == promptID && $0.circleID == circleID }
    }

    private func installTimelinePage(_ page: TimelinePage, circleID: UUID, reset: Bool = false) {
        guard let userID = currentUser?.id else { return }
        invalidateTimelineResponders()
        lastVisibleReadAt = .now
        let scope = TimelinePaging.scope(circleID: circleID, viewerID: userID,
            timeZoneIdentifier: circle?.timeZoneIdentifier ?? TimeZone.current.identifier)
        if reset || timelinePagingScope != scope {
            timelineHasLoadedMore = false
            timelinePagingScope = scope
            lanes = page.lanes
        } else { lanes = TimelinePaging.merge(lanes, with: page.lanes) }
        mergeSavedHistory(now: .now)
        if !timelineHasLoadedMore { timelineNextBeforeDate = page.nextBeforeDate }
        timelineLoadError = nil
        scheduleStreakRefresh()
    }

    func loadMoreTimeline() async {
        guard canUseFreshCircle else { return }
        guard !isLoadingMoreTimeline, let cursor = timelineNextBeforeDate, let circle, let currentUser else { return }
        isLoadingMoreTimeline = true
        defer { isLoadingMoreTimeline = false }
        let generation = dataScopeGeneration
        do {
            let page = try await repository.timelinePage(circleID: circle.id, viewerID: currentUser.id, now: .now, before: cursor)
            guard !Task.isCancelled, dataScopeGeneration == generation,
                  self.circle?.id == circle.id, self.circle?.timeZoneIdentifier == circle.timeZoneIdentifier,
                  self.currentUser?.id == currentUser.id, timelineNextBeforeDate == cursor else { return }
            lanes = TimelinePaging.merge(lanes, with: page.lanes)
            mergeSavedHistory(now: .now)
            timelineNextBeforeDate = page.nextBeforeDate
            timelineHasLoadedMore = true
            timelineLoadError = nil
        } catch {
            guard dataScopeGeneration == generation, !Task.isCancelled, !Self.isCancellation(error) else { return }
            timelineLoadError = "Couldn’t load older days. Try again."
        }
    }

    func refreshCurrentCircle(now: Date = .now, force: Bool = true) async {
        if !force, let lastVisibleReadAt, now.timeIntervalSince(lastVisibleReadAt) < 15 { return }
        guard !isPageLoading, !isSwitchingCircle, !isShowingCachedMetadata else { return }
        let operation = UUID()
        pageLoadGeneration = operation
        isPageLoading = true
        pageLoadError = nil
        defer { if pageLoadGeneration == operation { isPageLoading = false } }
        let generation = dataScopeGeneration
        do {
            try await reloadCurrentCircle(now: now)
        } catch {
            guard dataScopeGeneration == generation, !Task.isCancelled, !Self.isCancellation(error) else { return }
            pageLoadError = "Couldn’t refresh your circle: \(error.localizedDescription)"
        }
    }

    func switchCircle(to circleID: UUID) async {
        if isShowingSavedTimeline, !isPageLoading, let savedCircle = circles.first(where: { $0.id == circleID }) {
            circle = savedCircle
            lanes = savedTimelineLanes(circleID: circleID, now: .now)
            Self.persistedCircleID = circleID
            return
        }
        guard !isSwitchingCircle, !isPageLoading, !isShowingCachedMetadata,
              circle?.id != circleID,
              circles.contains(where: { $0.id == circleID }),
              let currentUser else { return }
        let span = BackendDiagnostics.shared.begin(.circleSwitch)
        var outcome = BackendOutcome.failure
        defer { span.finish(Task.isCancelled ? .cancelled : outcome) }
        isSwitchingCircle = true
        let operation = UUID()
        pageLoadGeneration = operation
        isPageLoading = true
        pageLoadError = nil
        let previousCircle = circle
        let previousPrompt = prompt, previousEvening = endOfDayPrompt
        let previousLanes = lanes
        defer {
            if pageLoadGeneration == operation { isSwitchingCircle = false; isPageLoading = false }
        }
        // Show the destination's local identity immediately; content is always fresh.
        circle = circles.first { $0.id == circleID }
        isShowingCachedMetadata = true
        prompt = nil; endOfDayPrompt = nil; lanes = []
        capturePrompt = nil; submittedBlessing = nil
        dataScopeGeneration = UUID()
        let generation = dataScopeGeneration
        realtimeTask?.cancel()
        realtimeTask = nil
        do {
            let (context, targetLanes) = try await loadCircleSwitchData(
                circleID: circleID,
                viewerID: currentUser.id
            )
            try Task.checkCancellation()
            guard dataScopeGeneration == generation,
                  self.currentUser?.id == currentUser.id else {
                if realtimeTask == nil, self.currentUser != nil { startRealtimeUpdates() }
                return
            }
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
            installTimelinePage(targetLanes, circleID: circleID, reset: true)
            isShowingCachedMetadata = false
            outcome = .success
            if let index = circles.firstIndex(where: { $0.id == circleID }) {
                circles[index] = resolvedCircle
            }
            Self.persistedCircleID = circleID
            await persistMetadata()
            scheduleWidgetSnapshotRefresh()
            startRealtimeUpdates()
            if let prompt = context.prompt, prompt.phase(at: .now) == .open {
                await startLiveActivity(for: prompt, circle: resolvedCircle)
            }
            await reloadDrafts()
        } catch {
            if dataScopeGeneration == generation, self.currentUser?.id == currentUser.id {
                circle = previousCircle; prompt = previousPrompt; endOfDayPrompt = previousEvening; lanes = previousLanes
                isShowingCachedMetadata = false
                // Restoring the original circle creates a new scope generation.
                if realtimeTask == nil { startRealtimeUpdates() }
                if !Self.isCancellation(error), !Task.isCancelled {
                    pageLoadError = "Couldn’t switch circles: \(error.localizedDescription)"
                }
                return
            }
            if dataScopeGeneration == generation, self.currentUser?.id == currentUser.id,
               realtimeTask == nil { startRealtimeUpdates() }
            guard dataScopeGeneration == generation, self.currentUser?.id == currentUser.id,
                  !Task.isCancelled else { return }
            message = Self.isCancellation(error)
                ? "The circle switch was interrupted. Please try again."
                : "Couldn’t switch circles: \(error.localizedDescription)"
        }
    }

    private func loadCircleSwitchData(
        circleID: UUID,
        viewerID: UUID
    ) async throws -> (CircleContext, TimelinePage) {
        var lastCancellation: Error?
        for attempt in 0..<3 {
            do {
                let context = try await repository.circleContext(circleID: circleID)
                let lanes = try await repository.timelinePage(circle: context.circle, viewerID: viewerID, now: .now, before: nil)
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
        let span = BackendDiagnostics.shared.begin(.circleRefresh)
        var outcome = BackendOutcome.failure
        defer { span.finish(Task.isCancelled ? .cancelled : outcome) }
        let generation = dataScopeGeneration
        let context = try await repository.circleContext(circleID: selectedCircleID)
        let refreshedLanes = try await repository.timelinePage(
            circle: context.circle,
            viewerID: currentUser.id,
            now: now, before: nil
        )
        guard !Task.isCancelled, dataScopeGeneration == generation,
              circle?.id == selectedCircleID, self.currentUser?.id == currentUser.id else { return }

        let knownInviteCode = circles.first(where: { $0.id == selectedCircleID })?.inviteCode
        let refreshedCircle = context.circle.preservingInviteCode(knownInviteCode)
        circle = refreshedCircle
        prompt = context.prompt
        endOfDayPrompt = context.endOfDayPrompt
        installTimelinePage(refreshedLanes, circleID: selectedCircleID)
        outcome = .success
        upsertCircle(refreshedCircle)
        await persistMetadata()
        scheduleWidgetSnapshotRefresh(now: now)

        if let prompt = context.prompt, prompt.phase(at: now) == .open {
            await startLiveActivity(for: prompt, circle: refreshedCircle)
        }
        await reloadDrafts(now: now)
    }

    private func activatePrompt(promptID: UUID, now: Date = .now) async -> Bool {
        guard canUseFreshCircle, let currentUser else { return false }
        isSwitchingCircle = true
        defer { isSwitchingCircle = false }

        dataScopeGeneration = UUID()
        let generation = dataScopeGeneration

        let previousCircleID = circle?.id
        var needsRealtimeRestart = false
        do {
            let context = try await repository.circleContext(promptID: promptID)
            guard !Task.isCancelled, dataScopeGeneration == generation,
                  self.currentUser?.id == currentUser.id else { return false }
            guard circles.contains(where: { $0.id == context.circle.id }) else {
                throw BlessingError.circleNotFound
            }
            if previousCircleID != context.circle.id {
                realtimeTask?.cancel()
                realtimeTask = nil
                needsRealtimeRestart = true
            }
            let refreshedLanes = try await repository.timelinePage(
                circle: context.circle,
                viewerID: currentUser.id,
                now: now, before: nil
            )
            guard !Task.isCancelled, dataScopeGeneration == generation,
                  self.currentUser?.id == currentUser.id else {
                if needsRealtimeRestart, realtimeTask == nil, self.currentUser != nil { startRealtimeUpdates() }
                return false
            }
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
            installTimelinePage(refreshedLanes, circleID: resolvedCircle.id, reset: previousCircleID != resolvedCircle.id)
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
            await reloadDrafts(now: now)
            return true
        } catch {
            if needsRealtimeRestart, dataScopeGeneration == generation,
               self.currentUser?.id == currentUser.id, realtimeTask == nil {
                startRealtimeUpdates()
            }
            guard dataScopeGeneration == generation, self.currentUser?.id == currentUser.id,
                  !Task.isCancelled, !Self.isCancellation(error) else { return false }
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
        guard canUseFreshCircle, let targetPrompt = capturePrompt ?? prompt, let currentUser else {
            message = BlessingError.outsideResponseWindow.localizedDescription
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let span = BackendDiagnostics.shared.begin(.submit)
        var outcome = BackendOutcome.failure
        defer { span.finish(Task.isCancelled ? .cancelled : outcome) }
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
            outcome = .success
            await clearSentDraft(promptID: targetPrompt.id, circleID: savedBlessing.circleID, authorID: currentUser.id)
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
                try await refreshAfterPosting()
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
        guard canUseFreshCircle, let currentUser else { return false }
        return BlessingEditPolicy.canEdit(blessing, authorID: currentUser.id, at: date)
    }

    func updateBlessing(
        _ blessing: Blessing,
        body: String,
        scriptureReference: ScriptureReference?
    ) async -> Blessing? {
        guard canUseFreshCircle, let currentUser else { return nil }
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
        guard !isShowingCachedMetadata, !isPageLoading, !isSwitchingCircle else { return false }
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
        guard !isShowingCachedMetadata, !isPageLoading, !isSwitchingCircle else { return false }
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

    private func isCurrentCircleMutation(circleID: UUID, userID: UUID, generation: UUID) -> Bool {
        !Task.isCancelled && !isSwitchingCircle && dataScopeGeneration == generation
            && circle?.id == circleID && currentUser?.id == userID
    }

    func setCircleMemberChanges(_ allowed: Bool) async -> Bool {
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.ownerID == currentUser.id,
              circle.members.contains(where: { $0.id == currentUser.id }) else {
            message = BlessingError.notCircleOwner.localizedDescription
            return false
        }
        let generation = dataScopeGeneration
        do {
            let updatedCircle = try await repository.setCircleMemberChanges(
                circleID: circle.id, ownerID: currentUser.id, allowed: allowed
            )
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
            message = error.localizedDescription
            return false
        }
    }

    func regenerateCurrentCircleInviteCode() async -> Bool {
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.canManageSettings(memberID: currentUser.id) else {
            message = BlessingError.circleChangesNotAllowed.localizedDescription
            return false
        }
        let generation = dataScopeGeneration
        do {
            let updatedCircle = try await repository.regenerateInviteCode(
                circleID: circle.id,
                ownerID: currentUser.id
            )
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            message = "A new circle code is ready. The previous code no longer works."
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
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
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.canManageSettings(memberID: currentUser.id) else {
            message = BlessingError.circleChangesNotAllowed.localizedDescription
            return false
        }
        var generation = dataScopeGeneration
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
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            generation = dataScopeGeneration
            try await reloadCurrentCircle(now: .now)
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            message = "Circle settings saved. The response length applies to future prompts."
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
            message = error.localizedDescription
            return false
        }
    }

    func updateCirclePhoto(_ photoURL: URL?) async -> Bool {
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.canManageSettings(memberID: currentUser.id) else {
            message = BlessingError.circleChangesNotAllowed.localizedDescription
            return false
        }
        let generation = dataScopeGeneration
        do {
            let updatedCircle = try await repository.updateCirclePhoto(
                circleID: circle.id,
                ownerID: currentUser.id,
                photoURL: photoURL
            )
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            scheduleWidgetSnapshotRefresh()
            message = photoURL == nil ? "Circle photo removed." : "Circle photo saved."
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
            message = error.localizedDescription
            return false
        }
    }

    func setCircleActivityNotifications(_ enabled: Bool, for circleID: UUID) async {
        guard canUseFreshCircle else { return }
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
        guard canUseFreshCircle else { return }
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
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.canManageSettings(memberID: currentUser.id) else {
            message = BlessingError.circleChangesNotAllowed.localizedDescription
            return false
        }
        guard !isForcingCirclePrompt else { return false }

        isForcingCirclePrompt = true
        defer { isForcingCirclePrompt = false }

        let generation = dataScopeGeneration
        do {
            let outcome = try await repository.forceCirclePrompt(
                circleID: circle.id,
                ownerID: currentUser.id,
                now: now
            )
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            await activityController.end()
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            prompt = outcome.prompt
            submittedBlessing = nil
            isCapturePresented = false
            capturePrompt = nil
            selectedTab = 0
#if DEBUG
            isDebugPromptPreview = false
#endif
            try await refreshTimeline(now: now)
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }

            if !usesAuthentication {
                let activityResult = await activityController.startIfNeeded(
                    prompt: outcome.prompt,
                    circle: circle,
                    requestsPushUpdates: false
                )
                guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
                message = "Local blessing test started for \(outcome.memberCount) members. \(activityResult.debugMessage)"
            } else if outcome.registeredDevices == 0 {
                message = "The blessing window is open, but no member devices are registered for notifications yet."
            } else {
                message = "The blessing window is open for \(outcome.memberCount) members. Apple accepted \(outcome.deliveredNotifications) of \(outcome.attemptedNotifications) notification and Live Activity requests across \(outcome.registeredDevices) devices."
            }
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
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
        guard canUseFreshCircle else { return false }
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
            await persistMetadata()
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
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.ownerID == currentUser.id && circle.members.contains(where: { $0.id == currentUser.id }) else {
            message = BlessingError.notCircleOwner.localizedDescription
            return false
        }
        let generation = dataScopeGeneration
        do {
            let updatedCircle = try await repository.transferCircleOwnership(
                circleID: circle.id,
                ownerID: currentUser.id,
                newOwnerID: newOwnerID
            )
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            scheduleWidgetSnapshotRefresh()
            let newOwnerName = updatedCircle.members
                .first(where: { $0.id == newOwnerID })?
                .displayName ?? "the new owner"
            message = "Ownership transferred to \(newOwnerName)."
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
            message = error.localizedDescription
            return false
        }
    }

    func removeMemberFromCurrentCircle(_ memberID: UUID) async -> Bool {
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        guard circle.canManageSettings(memberID: currentUser.id) else {
            message = BlessingError.circleChangesNotAllowed.localizedDescription
            return false
        }
        guard memberID != circle.ownerID, memberID != currentUser.id else {
            message = BlessingError.invalidMemberRemoval.localizedDescription
            return false
        }
        let generation = dataScopeGeneration
        do {
            let updatedCircle = try await repository.removeCircleMember(
                circleID: circle.id,
                ownerID: currentUser.id,
                memberID: memberID
            )
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            let resolvedCircle = updatedCircle.preservingInviteCode(circle.inviteCode)
            self.circle = resolvedCircle
            upsertCircle(resolvedCircle)
            try await refreshTimeline(now: .now)
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
            scheduleWidgetSnapshotRefresh()
            message = "Member removed from \(updatedCircle.name)."
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation),
                  !Self.isCancellation(error) else { return false }
            message = error.localizedDescription
            return false
        }
    }

    func repeatBlessingCandidates(now: Date = .now) async -> [Blessing] {
        guard canUseFreshCircle else { return [] }
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
        guard canUseFreshCircle else { return false }
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
            await clearSentDraft(promptID: targetPrompt.id, circleID: savedBlessing.circleID, authorID: currentUser.id)
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
                try await refreshAfterPosting(now: now)
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
        guard canUseFreshCircle, let circle, let currentUser else { return false }
        let generation = dataScopeGeneration
        do {
            try await repository.leaveCircle(circleID: circle.id, memberID: currentUser.id)
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
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
            let completionGeneration = dataScopeGeneration
            await persistMetadata()
            await IdentityPhotoCache.shared.clear(accountID: currentUser.id)
            guard self.currentUser?.id == currentUser.id, dataScopeGeneration == completionGeneration, !Task.isCancelled else { return true }
            if let nextCircle = circles.first {
                Self.persistedCircleID = nextCircle.id
                await switchCircle(to: nextCircle.id)
            } else {
                Self.persistedCircleID = nil
                selectedTab = 2
                scheduleWidgetSnapshotRefresh()
            }
            guard self.currentUser?.id == currentUser.id, !Task.isCancelled else { return true }
            message = "You left \(leftName)."
            return true
        } catch {
            guard isCurrentCircleMutation(circleID: circle.id, userID: currentUser.id, generation: generation) else { return false }
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

    private func invalidateTimelineResponders() {
        // Replace the cache synchronously: old in-flight batches can finish only in their old instance.
        timelineResponderCache = TimelineResponderSummaryCache()
        timelineResponderRevision = UUID()
    }

    func timelineResponseSummary(for blessing: Blessing, revision: UUID) async -> TimelineResponseSummary? {
        if isShowingSavedTimeline {
            guard !Task.isCancelled, revision == timelineResponderRevision,
                  timelineVisibleBlessingIDs.contains(blessing.id),
                  blessing.circleID == circle?.id,
                  let saved = savedBlessings[blessing.id] else { return nil }
            return TimelineResponseSummary(count: saved.responses.count,
                authorIDs: Array(Set(saved.responses.map(\.authorID))).sorted { $0.uuidString < $1.uuidString },
                responseAudioDates: saved.responses.filter { $0.mode == .voice }.map(\.submittedAt))
        }
        guard !Task.isCancelled, revision == timelineResponderRevision,
              canUseFreshCircle, let currentUser, let circle,
              blessing.circleID == circle.id,
              timelineVisibleBlessingIDs.contains(blessing.id) else { return nil }
        let generation = dataScopeGeneration
        let cache = timelineResponderCache
        do {
            let summary = try await cache.summary(for: blessing.id) { [repository] ids in
                try await repository.timelineResponderSummaries(blessingIDs: ids, viewerID: currentUser.id)
            }
            guard !Task.isCancelled, revision == timelineResponderRevision,
                  generation == dataScopeGeneration, canUseFreshCircle,
                  self.currentUser?.id == currentUser.id, self.circle?.id == circle.id else { return nil }
            responseMediaDates[blessing.id] = summary.responseAudioDates
            let members = Set(circle.members.map(\.id))
            return TimelineResponseSummary(count: summary.count,
                authorIDs: summary.authorIDs.filter { members.contains($0) },
                responseAudioDates: summary.responseAudioDates)
        } catch {
            // Avatar previews are optional. Detail views retain the complete response error/retry flow.
            return nil
        }
    }

    func responses(for blessing: Blessing) async -> [BlessingResponse] {
        if isShowingSavedTimeline { return savedBlessings[blessing.id]?.responses ?? [] }
        guard canUseFreshCircle else { return [] }
        guard let currentUser else { return [] }
        do {
            let responses = try await repository.responses(blessingID: blessing.id, viewerID: currentUser.id)
            responseMediaDates[blessing.id] = responses.filter { $0.mode == .voice }.map(\.submittedAt)
            if savedBlessings[blessing.id]?.isAutomatic == true { scheduleAutomaticSaving() }
            return responses.map { resolvedResponse($0) }
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return [] }
            if let saved = savedBlessings[blessing.id] { return saved.responses }
            message = error.localizedDescription
            return []
        }
    }

    func resolvedResponse(_ response: BlessingResponse, at now: Date = .now) -> BlessingResponse {
        let local = existingLocalFile(savedBlessings[response.blessingID]?.responses.first { $0.id == response.id }?.audioURL)
        return response.replacingAudio(local ?? (MediaRetentionPolicy.isExpired(submittedAt: response.submittedAt, at: now)
            ? nil : response.audioURL))
    }

    func resolvedBlessing(_ blessing: Blessing, at now: Date = .now) -> Blessing {
        if isShowingSavedTimeline, let local = savedBlessings[blessing.id]?.blessing { return local }
        let saved = savedBlessings[blessing.id]?.blessing
        let expired = MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt, at: now)
        return blessing.replacingMedia(
            audio: existingLocalFile(saved?.audioURL) ?? (expired ? nil : blessing.audioURL),
            video: existingLocalFile(saved?.videoURL) ?? (expired ? nil : blessing.videoURL),
            photo: existingLocalFile(saved?.photoURL) ?? blessing.photoURL
        )
    }

    private func existingLocalFile(_ url: URL?) -> URL? {
        guard let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
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
            if currentUser?.id == userID {
                savedBlessings.removeValue(forKey: blessing.id)
                if isShowingSavedTimeline { lanes = savedTimelineLanes(circleID: circle?.id, now: .now) }
            }
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

    func setAutomaticSavingNetwork(wifiOnly: Bool) async {
        guard let userID = currentUser?.id else { return }
        var preferences = localSavingPreferences
        preferences.wifiOnly = wifiOnly
        do {
            try await savedBlessingStore.savePreferences(preferences, userID: userID)
            guard currentUser?.id == userID else { return }
            localSavingPreferences = preferences
            automaticSavingWaitingForWiFi = false
            scheduleAutomaticSaving()
        } catch { automaticSavingError = "Couldn’t change download settings. Try again." }
    }

    func setAutomaticSavingHistory(_ includesOlder: Bool) async {
        guard let userID = currentUser?.id else { return }
        var preferences = localSavingPreferences
        preferences.includesOlderHistory = includesOlder
        do {
            try await savedBlessingStore.savePreferences(preferences, userID: userID)
            guard currentUser?.id == userID else { return }
            localSavingPreferences = preferences
            automaticHistoryCursors = [:]; automaticHistoryCompleted = []
            scheduleAutomaticSaving()
        } catch { automaticSavingError = "Couldn’t change history saving. Try again." }
    }

    /// Optional workers share a short-lived authorized page, never an unbounded timeline.
    private func backgroundCircleRead(_ membership: CircleGroup, now: Date) async throws -> BackgroundRead {
        guard let userID = currentUser?.id, canUseFreshCircle else { throw CancellationError() }
        if membership.id == circle?.id, let circle, let lastVisibleReadAt,
           now.timeIntervalSince(lastVisibleReadAt) < 60 {
            return BackgroundRead(context: CircleContext(circle: circle, prompt: prompt, endOfDayPrompt: endOfDayPrompt),
                page: TimelinePage(lanes: lanes, nextBeforeDate: timelineNextBeforeDate), date: lastVisibleReadAt)
        }
        if let cached = backgroundReads[membership.id], now.timeIntervalSince(cached.date) < 60 { return cached }
        if let work = backgroundReadTasks[membership.id] { return try await work.value }
        let generation = dataScopeGeneration
        let repository = self.repository
        let work = Task {
            let context = try await repository.circleContext(circleID: membership.id)
            let page = try await repository.timelinePage(circle: context.circle, viewerID: userID, now: now, before: nil)
            return BackgroundRead(context: context, page: page, date: now)
        }
        backgroundReadTasks[membership.id] = work
        defer { if dataScopeGeneration == generation { backgroundReadTasks[membership.id] = nil } }
        let result = try await work.value
        guard currentUser?.id == userID, dataScopeGeneration == generation, !Task.isCancelled else { throw CancellationError() }
        backgroundReads[membership.id] = result
        return result
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

    func resumeAutomaticSavingAfterNetworkChange() {
        if automaticSavingWaitingForWiFi { scheduleAutomaticSaving() }
    }

    private func scheduleAutomaticSaving() {
        guard runsBackgroundRefreshes else { return }
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
                while self.isPageLoading || self.isSwitchingCircle || self.isShowingCachedMetadata {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
                await self.saveVisibleBlessingsAutomatically()
            } while self.automaticSaveNeedsAnotherPass && !Task.isCancelled && self.automaticallySavesLocally
        }
    }

    // Can also be awaited by local regression tests; production calls run away
    // from the main screen's loading lifecycle and never surface scrolling alerts.
    func saveVisibleBlessingsAutomatically() async {
        guard let userID = currentUser?.id, automaticallySavesLocally, !isChoosingAutomaticSaving else { return }
        if authentication != nil {
            let allowed = await networkSavingPolicy.permitsAutomaticDownloads(wifiOnly: automaticallySavesOnWiFiOnly)
            guard currentUser?.id == userID, !Task.isCancelled else { return }
            automaticSavingWaitingForWiFi = !allowed
            guard allowed else { return }
        }
        automaticSavingWaitingForWiFi = false
        let span = BackendDiagnostics.shared.begin(.automaticSaving)
        var outcome = BackendOutcome.failure
        defer { span.finish(Task.isCancelled ? .cancelled : outcome) }
        let memberships = circles
        var failures = 0
        for membership in memberships {
            do {
                try Task.checkCancellation()
                let read = try await backgroundCircleRead(membership, now: .now)
                var visibleLanes = read.page.lanes
                let failuresBeforeCircle = failures
                var readOlderPage = false
                var nextOlderCursor: Date?
                if automaticallySavesOlderHistory, !automaticHistoryCompleted.contains(membership.id) {
                    let cursor = automaticHistoryCursors[membership.id] ?? read.page.nextBeforeDate
                    if let cursor {
                        let older = try await repository.timelinePage(circle: read.context.circle, viewerID: userID, now: .now, before: cursor)
                        visibleLanes += older.lanes
                        readOlderPage = true
                        nextOlderCursor = older.nextBeforeDate
                    } else { automaticHistoryCompleted.insert(membership.id) }
                }
                let cutoff = Date.now.addingTimeInterval(-7 * 86_400)
                let blessings = Array(Dictionary(visibleLanes.flatMap(\.events).compactMap { event -> (UUID, Blessing)? in
                    guard case let .blessing(blessing) = event.status,
                          automaticallySavesOlderHistory || blessing.submittedAt >= cutoff else { return nil }
                    return (blessing.id, blessing)
                }, uniquingKeysWith: { first, _ in first }).values)
                var responseCounts: [UUID: Int] = [:]
                // Reuse the visible-card summary batcher; unchanged archives never fetch response bodies/audio links.
                let savedIDs = blessings.filter { savedBlessings[$0.id]?.isAutomatic == true }.map(\.id)
                let cache = timelineResponderCache
                let repository = self.repository
                await withTaskGroup(of: (UUID, Int?).self) { group in
                    for id in savedIDs {
                        group.addTask {
                            let summary = try? await cache.summary(for: id) { ids in
                                try await repository.timelineResponderSummaries(blessingIDs: ids, viewerID: userID)
                            }
                            return (id, summary?.count)
                        }
                    }
                    for await (id, count) in group { responseCounts[id] = count }
                }
                for blessing in blessings {
                    try Task.checkCancellation()
                    guard currentUser?.id == userID, automaticallySavesLocally,
                          circles.contains(where: { $0.id == blessing.circleID }) else { return }
                    guard !localSavingPreferences.excludedBlessingIDs.contains(blessing.id),
                          !savingBlessingIDs.contains(blessing.id) else { continue }
                    let existing = savedBlessings[blessing.id]
                    if let existing, !existing.isAutomatic { continue }
                    if let existing, existing.hasAllSavedFiles, existing.blessing.body == blessing.body,
                       existing.blessing.scriptureReference == blessing.scriptureReference,
                       existing.blessing.editedAt == blessing.editedAt,
                       responseCounts[blessing.id] == existing.responses.count { continue }
                    if authentication != nil {
                        guard await networkSavingPolicy.permitsAutomaticDownloads(wifiOnly: automaticallySavesOnWiFiOnly) else {
                            automaticSavingWaitingForWiFi = true; return
                        }
                    }
                    savingBlessingIDs.insert(blessing.id)
                    do {
                        defer { savingBlessingIDs.remove(blessing.id) }
                        let responses = try await repository.responses(blessingID: blessing.id, viewerID: userID)
                        if let existing, existing.hasAllSavedFiles,
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
                            userID: userID, automatically: true, refreshing: existing != nil, wifiOnly: automaticallySavesOnWiFiOnly)
                        guard currentUser?.id == userID, !Task.isCancelled else { return }
                        savedBlessings[blessing.id] = record
                    } catch {
                        if Task.isCancelled || Self.isCancellation(error) { return }
                        if authentication != nil,
                           !(await networkSavingPolicy.permitsAutomaticDownloads(wifiOnly: automaticallySavesOnWiFiOnly)) {
                            automaticSavingWaitingForWiFi = true; return
                        }
                        failures += 1
                    }
                }
                if readOlderPage, failures == failuresBeforeCircle {
                    automaticHistoryCursors[membership.id] = nextOlderCursor
                    if nextOlderCursor == nil { automaticHistoryCompleted.insert(membership.id) }
                }
            } catch {
                if Task.isCancelled || Self.isCancellation(error) { return }
                failures += 1
            }
        }
        if currentUser?.id == userID {
            automaticSavingError = failures == 0 ? nil
                : "Some blessings couldn’t be saved. Available copies will retry next time the app refreshes."
            outcome = failures == 0 ? .success : .failure
        }
    }

    func canRespond(to blessing: Blessing, at date: Date = .now) -> Bool {
        guard canUseFreshCircle else { return false }
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
        guard canUseFreshCircle else { return nil }
        guard let currentUser else { return nil }
        let generation = dataScopeGeneration
        do {
            let response = try await repository.submitResponse(
                blessingID: blessing.id,
                circleID: blessing.circleID,
                authorID: currentUser.id,
                mode: mode,
                body: body,
                audioURL: audioURL,
                now: .now
            )
            if dataScopeGeneration == generation, self.currentUser?.id == currentUser.id {
                invalidateTimelineResponders()
            }
            return response
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
            guard let blessingID = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return }
            var item = blessingFeedItem(id: blessingID)
            if item == nil, let userID = currentUser?.id {
                do {
                    if let blessing = try await repository.blessing(id: blessingID, viewerID: userID),
                       currentUser?.id == userID, blessing.circleID == circle?.id,
                       let member = circle?.members.first(where: { $0.id == blessing.authorID }) {
                        item = BlessingFeedItem(member: member, blessing: resolvedBlessing(blessing))
                    }
                } catch {
                    guard !Self.isCancellation(error) else { return }
                    message = "This blessing couldn’t be opened. Try again."
                }
            }
            guard let item else { return }
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

    /// Posting changes metadata as well as content. Fetch one fresh context and
    /// pass it into the page read so all streak surfaces update together.
    private func refreshAfterPosting(now: Date = .now) async throws {
        let generation = dataScopeGeneration
        while isPageLoading || isSwitchingCircle {
            try await Task.sleep(for: .milliseconds(100))
            guard dataScopeGeneration == generation else { return }
        }
        guard canUseFreshCircle, dataScopeGeneration == generation else { return }
        let operation = UUID()
        pageLoadGeneration = operation
        isPageLoading = true
        defer { if pageLoadGeneration == operation { isPageLoading = false } }
        try await reloadCurrentCircle(now: now)
    }

    /// Server-authored streak deadlines let an idle visible circle resolve a
    /// missed day without polling every second or waiting for a new launch.
    private func scheduleStreakRefresh(now: Date = .now) {
        streakRefreshTask?.cancel()
        streakRefreshTask = nil
        nextStreakRefreshAt = nil
        guard runsBackgroundRefreshes, let circle, let accountID = currentUser?.id else { return }
        var deadlines = (circle.streaks?.values.compactMap(\.nextUpdateAt) ?? [])
        for candidate in [prompt, endOfDayPrompt].compactMap({ $0 }) where candidate.circleID == circle.id {
            deadlines.append(candidate.startsAt)
            deadlines.append(candidate.endsAt)
        }
        let calendar = CircleLocalDay.calendar(timeZoneIdentifier: circle.timeZoneIdentifier)
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            deadlines.append(nextDay)
        }
        guard let deadline = deadlines.filter({ $0 > now }).min() else { return }
        nextStreakRefreshAt = deadline
        let generation = dataScopeGeneration
        streakRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.1, deadline.timeIntervalSinceNow + 0.35))) }
            catch { return }
            guard let self else { return }
            // An in-flight visible load will install its own deadline. Give it a
            // bounded chance to finish rather than overlapping that backend read.
            for _ in 0..<20 {
                guard !Task.isCancelled, self.dataScopeGeneration == generation,
                      self.currentUser?.id == accountID, self.circle?.id == circle.id else { return }
                if !self.isPageLoading && !self.isSwitchingCircle { break }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            guard !Task.isCancelled, self.dataScopeGeneration == generation,
                  self.loadState == .ready, self.canUseFreshCircle,
                  !self.isPageLoading, !self.isSwitchingCircle else { return }
            // The load will schedule its successor; do not cancel its own task.
            self.streakRefreshTask = nil
            await self.refreshCurrentCircle()
            guard !Task.isCancelled, self.dataScopeGeneration == generation else { return }
            self.scheduleStreakRefresh()
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
                    await self?.refreshCurrentCircle(now: .now)
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
        metadataSaveTask?.cancel()
        metadataSaveTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.persistMetadata()
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
        guard runsBackgroundRefreshes else { return }
        // Frequent realtime/scroll refreshes must not starve a multi-circle fetch.
        widgetSnapshotPendingDate = now
        guard widgetSnapshotTask == nil else { return }
        widgetSnapshotTask = Task { [weak self] in
            guard let self else { return }
            while let requestedDate = self.widgetSnapshotPendingDate {
                // Visible circle reads take priority over optional cross-circle
                // widget work, especially during startup and switching.
                while self.isPageLoading || self.isSwitchingCircle || self.isShowingCachedMetadata {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                self.widgetSnapshotPendingDate = nil
                await self.writeWidgetSnapshot(now: requestedDate)
            }
            self.widgetSnapshotTask = nil
        }
    }

    func writeWidgetSnapshot(now: Date) async {
        guard let currentUser else {
            BlessingWidgetSnapshotStore.save(.empty)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        if let lastWidgetWriteAt, now.timeIntervalSince(lastWidgetWriteAt) < 60, lastWidgetRevision == timelineResponderRevision { return }
        let generation = dataScopeGeneration
        let span = BackendDiagnostics.shared.begin(.widgetRefresh)
        var outcome = BackendOutcome.failure
        defer { span.finish(Task.isCancelled ? .cancelled : outcome) }

        struct Candidate {
            let circle: CircleGroup
            let member: Member
            let blessing: Blessing
            let isFromCurrentCircleDay: Bool
        }

        var promptSnapshots: [BlessingWidgetPrompt] = []
        var candidates: [Candidate] = []
        var loadedCircles = 0

        for membership in circles {
            guard !Task.isCancelled else { return }
            do {
                let read = try await backgroundCircleRead(membership, now: now)
                let context = read.context
                let circleLanes = read.page.lanes
                loadedCircles += 1
                let currentPromptIsToday = context.prompt?.occursOnCircleDay(
                    at: now,
                    timeZoneIdentifier: context.circle.timeZoneIdentifier
                ) == true

                if let prompt = context.prompt, currentPromptIsToday,
                   prompt.notificationHasStarted != false || prompt.startsAt > now {
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

        if loadedCircles > 0 { lastWidgetWriteAt = now; lastWidgetRevision = timelineResponderRevision }
        // A temporary connection failure must not replace usable widget data with nothing.
        guard circles.isEmpty || loadedCircles > 0 else { return }
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
        guard !Task.isCancelled, self.currentUser?.id == currentUser.id, dataScopeGeneration == generation else { return }
        BlessingWidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        outcome = loadedCircles == circles.count ? .success : .failure

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
        guard !Task.isCancelled, self.currentUser?.id == currentUser.id, !loadedPassages.isEmpty else { return }
        for index in snapshot.blessings.indices {
            snapshot.blessings[index].scriptureText = loadedPassages[snapshot.blessings[index].id]
        }
        BlessingWidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func configureRemoteServices() async {
        guard usesAuthentication, registersForRemoteNotifications, !remoteServicesConfigured else { return }
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
