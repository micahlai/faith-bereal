import Foundation
import Observation
import UIKit
import UserNotifications

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

    init(
        repository: any BlessingRepository,
        bibleService: any BibleTextProviding = BibleAPIService(),
        authentication: (any AuthenticationProviding)? = nil
    ) {
        self.repository = repository
        self.bibleService = bibleService
        self.authentication = authentication
    }

    var hasSubmittedToday: Bool {
        guard let currentUser, let prompt else { return false }
        if submittedBlessing?.promptID == prompt.id { return true }
        return lanes
            .first(where: { $0.member.id == currentUser.id })?
            .events
            .contains(where: { event in
                if case let .blessing(blessing) = event.status {
                    return blessing.promptID == prompt.id
                }
                return false
            }) == true
    }

    var canSubmitCurrentPrompt: Bool {
        guard let prompt, let circle, !hasSubmittedToday else { return false }
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
            if let prompt = bootstrap.prompt,
               let circle = bootstrap.circle,
               prompt.phase(at: .now) == .open {
                await activityController.startIfNeeded(prompt: prompt, circle: circle)
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
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshTimeline(now: Date = .now) async throws {
        guard let circle, let currentUser else { return }
        lanes = try await repository.timeline(circleID: circle.id, viewerID: currentUser.id, now: now)
    }

    func switchCircle(to circleID: UUID) async {
        guard circle?.id != circleID, circles.contains(where: { $0.id == circleID }) else { return }
        isSwitchingCircle = true
        defer { isSwitchingCircle = false }
        do {
            let context = try await repository.circleContext(circleID: circleID)
            circle = context.circle
            prompt = context.prompt
            submittedBlessing = nil
            lanes = []
            if let index = circles.firstIndex(where: { $0.id == circleID }) {
                circles[index] = context.circle
            }
            Self.persistedCircleID = circleID
            try await refreshTimeline()
            startRealtimeUpdates()
            if let prompt = context.prompt, prompt.phase(at: .now) == .open {
                await activityController.startIfNeeded(prompt: prompt, circle: context.circle)
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
        scriptureReference: ScriptureReference?
    ) async -> Bool {
        guard let prompt, let currentUser else { return false }
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
                scriptureReference: scriptureReference,
                now: .now
            )
            try await refreshTimeline()
            await activityController.markSubmitted(responseCount: lanes.compactMap { lane in
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
        allowsLateBlessings: Bool
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
                allowsLateBlessings: allowsLateBlessings
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

    var bibleTranslations: [BibleTranslation] { BibleTranslation.publicDomain }
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
        } catch {
            message = error.localizedDescription
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

    func receiveAPNSToken(_ token: String) {
        apnsToken = token
        Task { await syncDeviceRegistration() }
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
            circles[index] = circle
        } else {
            circles.append(circle)
        }
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
