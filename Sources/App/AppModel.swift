import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private let repository: any BlessingRepository
    private let activityController = PromptActivityController()

    var loadState: LoadState = .idle
    var currentUser: Member?
    var circle: CircleGroup?
    var prompt: DailyPrompt?
    var lanes: [TimelineLane] = []
    var selectedTab = 0
    var isCapturePresented = false
    var isSubmitting = false
    var message: String?
    var submittedBlessing: Blessing?

    init(repository: any BlessingRepository) {
        self.repository = repository
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
        do {
            let (user, circle, prompt) = try await repository.bootstrap()
            self.currentUser = user
            self.circle = circle
            self.prompt = prompt
            try await refreshTimeline()
            loadState = .ready
            if prompt.phase(at: .now) == .open {
                await activityController.startIfNeeded(prompt: prompt, circle: circle)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func refreshTimeline(now: Date = .now) async throws {
        guard let circle, let currentUser else { return }
        lanes = try await repository.timeline(circleID: circle.id, viewerID: currentUser.id, now: now)
    }

    func submit(mode: CaptureMode, body: String?, videoURL: URL?) async -> Bool {
        guard let prompt, let currentUser else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            submittedBlessing = try await repository.submit(
                promptID: prompt.id,
                authorID: currentUser.id,
                mode: mode,
                body: body,
                videoURL: videoURL,
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
            circle = try await repository.joinCircle(code: code, memberID: currentUser.id)
            try await refreshTimeline()
            message = "You joined \(circle?.name ?? "the circle")."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func createCircle(name: String) async -> Bool {
        guard let currentUser else { return false }
        do {
            circle = try await repository.createCircle(name: name, member: currentUser)
            try await refreshTimeline()
            message = "Your new circle is ready."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func updateCircleSettings(responseWindowMinutes: Int, allowsLateBlessings: Bool) async -> Bool {
        guard let circle, let currentUser else { return false }
        do {
            self.circle = try await repository.updateCircleSettings(
                circleID: circle.id,
                ownerID: currentUser.id,
                responseWindowMinutes: responseWindowMinutes,
                allowsLateBlessings: allowsLateBlessings
            )
            message = "Circle settings saved. The response length applies to future prompts."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
