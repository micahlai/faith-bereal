@preconcurrency import ActivityKit
import Foundation

@MainActor
final class PromptActivityController {
    private var activity: Activity<PromptActivityAttributes>?
    private var observationTasks: [Task<Void, Never>] = []
    private var activityTokenTasks: [String: Task<Void, Never>] = [:]

    typealias PushToStartHandler = @Sendable (String) async -> Void
    typealias ActivityTokenHandler = @Sendable (UUID, String, String) async -> Void

    func startMonitoringTokens(
        onPushToStartToken: @escaping PushToStartHandler,
        onActivityToken: @escaping ActivityTokenHandler
    ) {
        guard observationTasks.isEmpty else { return }

        for existingActivity in Activity<PromptActivityAttributes>.activities {
            monitorPushTokens(for: existingActivity, handler: onActivityToken)
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
                self.monitorPushTokens(for: newActivity, handler: onActivityToken)
            }
        })
    }

    func startIfNeeded(prompt: DailyPrompt, circle: CircleGroup) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }
        let attributes = PromptActivityAttributes(promptID: prompt.id, circleName: circle.name)
        let state = PromptActivityAttributes.ContentState(
            endsAt: prompt.endsAt,
            responseCount: 0,
            hasSubmitted: false
        )
        do {
            let newActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: prompt.endsAt),
                pushType: .token
            )
            activity = newActivity
        } catch {
            // The app remains fully usable when Live Activities are disabled or unavailable.
        }
    }

    func markSubmitted(responseCount: Int) async {
        guard let activity else { return }
        let state = PromptActivityAttributes.ContentState(
            endsAt: activity.content.state.endsAt,
            responseCount: responseCount,
            hasSubmitted: true
        )
        await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .default)
        self.activity = nil
    }


    func stopMonitoringTokens() {
        observationTasks.forEach { $0.cancel() }
        activityTokenTasks.values.forEach { $0.cancel() }
        observationTasks.removeAll()
        activityTokenTasks.removeAll()
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
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
