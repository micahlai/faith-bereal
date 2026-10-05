#if DEBUG
import Foundation

/// A debug-build-only hook for exercising the complete prompt and submission flow
/// without changing hosted circle data.
protocol DebugPromptProviding: Sendable {
    func beginDebugPrompt(circleID: UUID, now: Date) async throws -> DailyPrompt
}
#endif
