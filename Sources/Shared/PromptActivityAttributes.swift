import ActivityKit
import Foundation

struct PromptActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endsAt: Date
        let responseCount: Int
        let hasSubmitted: Bool
    }

    let promptID: UUID
    let circleName: String
}

