@preconcurrency import ActivityKit
import Foundation
import OSLog

enum PromptActivityStartResult: Equatable {
    case started
    case alreadyRunning
    case disabled
    case failed(String)

    var debugMessage: String {
        switch self {
        case .started:
            "Live Activity started."
        case .alreadyRunning:
            "Live Activity is already running."
        case .disabled:
            "Live Activities are off for manna circle. Enable them in Settings, then try again."
        case let .failed(message):
            "Live Activity couldn’t start: \(message)"
        }
    }
}

@MainActor
final class PromptActivityController {
    private let logger = Logger(subsystem: "app.blessingcircle.ios", category: "LiveActivity")
    private var activitiesByPromptID: [UUID: Activity<PromptActivityAttributes>] = [:]
    private var observationTasks: [Task<Void, Never>] = []
    private var activityTokenTasks: [String: Task<Void, Never>] = [:]
    private var dismissalTasks: [UUID: Task<Void, Never>] = [:]

    typealias PushToStartHandler = @Sendable (String) async -> Void
    typealias ActivityTokenHandler = @Sendable (UUID, String, String) async -> Void

    func startMonitoringTokens(
        onPushToStartToken: @escaping PushToStartHandler,
        onActivityToken: @escaping ActivityTokenHandler
    ) {
        guard observationTasks.isEmpty else { return }

        for existingActivity in Activity<PromptActivityAttributes>.activities {
            activitiesByPromptID[existingActivity.attributes.promptID] = existingActivity
            monitorPushTokens(for: existingActivity, handler: onActivityToken)
            scheduleDismissalIfNeeded(for: existingActivity)
        }

        observationTasks.append(Task {
            for await tokenData in Activity<PromptActivityAttributes>.pushToStartTokenUpdates {
                guard !Task.isCancelled else { break }
                await onPushToStartToken(tokenData.hexString)
            }
        })
        observationTasks.append(Task {
            for await newActivity in Activity<PromptActivityAttributes>.activityUpdates {
                guard !Task.isCancelled else { break }
                self.activitiesByPromptID[newActivity.attributes.promptID] = newActivity
                self.monitorPushTokens(for: newActivity, handler: onActivityToken)
                self.scheduleDismissalIfNeeded(for: newActivity)
            }
        })
    }

    @discardableResult
    func startIfNeeded(
        prompt: DailyPrompt,
        circle: CircleGroup,
        requestsPushUpdates: Bool
    ) async -> PromptActivityStartResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities are disabled for the app")
            return .disabled
        }
        if let existingActivity = activity(for: prompt.id) {
            activitiesByPromptID[prompt.id] = existingActivity
            return .alreadyRunning
        }
        let attributes = PromptActivityAttributes(promptID: prompt.id, circleName: circle.name)
        let state = PromptActivityAttributes.ContentState(
            endsAt: prompt.endsAt,
            responseCount: 0,
            hasSubmitted: false,
            allowsLateBlessings: circle.allowsLateBlessings,
            dismissesAt: circle.allowsLateBlessings
                ? nil
                : PromptActivityDismissal.date(after: prompt.endsAt)
        )
        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: circle.allowsLateBlessings ? nil : prompt.endsAt
                ),
                pushType: requestsPushUpdates ? .token : nil
            )
            activitiesByPromptID[prompt.id] = newActivity
            scheduleDismissalIfNeeded(for: newActivity)
            logger.notice("Started Live Activity for prompt \(prompt.id.uuidString, privacy: .public)")
            return .started
        } catch {
            logger.error("Could not start Live Activity: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    func markSubmitted(promptID: UUID, responseCount: Int) async {
        guard let activity = activity(for: promptID) else { return }
        activitiesByPromptID[promptID] = activity
        let state = PromptActivityAttributes.ContentState(
            endsAt: activity.content.state.endsAt,
            responseCount: responseCount,
            hasSubmitted: true,
            allowsLateBlessings: activity.content.state.allowsLateBlessings,
            dismissesAt: PromptActivityDismissal.date(after: .now)
        )
        guard let dismissesAt = state.dismissesAt else { return }
        dismissalTasks[promptID]?.cancel()
        dismissalTasks[promptID] = nil
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .after(dismissesAt)
        )
        activitiesByPromptID[promptID] = nil
    }

    func end() async {
        let activities = Activity<PromptActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        dismissalTasks.values.forEach { $0.cancel() }
        dismissalTasks.removeAll()
        activitiesByPromptID.removeAll()
    }


    func stopMonitoringTokens() {
        observationTasks.forEach { $0.cancel() }
        activityTokenTasks.values.forEach { $0.cancel() }
        dismissalTasks.values.forEach { $0.cancel() }
        observationTasks.removeAll()
        activityTokenTasks.removeAll()
        dismissalTasks.removeAll()
    }

    private func monitorPushTokens(
        for activity: Activity<PromptActivityAttributes>,
        handler: @escaping ActivityTokenHandler
    ) {
        guard activityTokenTasks[activity.id] == nil else { return }
        activityTokenTasks[activity.id] = Task {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                await handler(activity.attributes.promptID, activity.id, tokenData.hexString)
            }
        }
    }

    private func activity(for promptID: UUID) -> Activity<PromptActivityAttributes>? {
        if let tracked = activitiesByPromptID[promptID],
           tracked.activityState == .active || tracked.activityState == .stale {
            return tracked
        }
        activitiesByPromptID[promptID] = nil
        return Activity<PromptActivityAttributes>.activities.first { activity in
            activity.attributes.promptID == promptID
                && (activity.activityState == .active || activity.activityState == .stale)
        }
    }

    private func scheduleDismissalIfNeeded(for activity: Activity<PromptActivityAttributes>) {
        let promptID = activity.attributes.promptID
        dismissalTasks[promptID]?.cancel()
        guard let dismissesAt = activity.content.state.dismissesAt else {
            dismissalTasks[promptID] = nil
            return
        }
        dismissalTasks[promptID] = Task { [weak self] in
            let delay = max(0, dismissesAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
            self?.activitiesByPromptID[promptID] = nil
            self?.dismissalTasks[promptID] = nil
        }
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
