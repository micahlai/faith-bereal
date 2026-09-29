@preconcurrency import ActivityKit
import Foundation

@MainActor
final class PromptActivityController {
    private var activity: Activity<PromptActivityAttributes>?

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
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: prompt.endsAt),
                pushType: .token
            )
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
}
