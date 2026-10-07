import ActivityKit
import Foundation

struct PromptActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endsAt: Date
        let responseCount: Int
        let hasSubmitted: Bool

        private enum CodingKeys: String, CodingKey {
            case endsAt
            case responseCount
            case hasSubmitted
        }

        init(endsAt: Date, responseCount: Int, hasSubmitted: Bool) {
            self.endsAt = endsAt
            self.responseCount = responseCount
            self.hasSubmitted = hasSubmitted
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawEndsAt = try container.decode(Double.self, forKey: .endsAt)
            endsAt = Self.date(fromWireTimestamp: rawEndsAt)
            responseCount = try container.decode(Int.self, forKey: .responseCount)
            hasSubmitted = try container.decode(Bool.self, forKey: .hasSubmitted)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(endsAt.timeIntervalSince1970, forKey: .endsAt)
            try container.encode(responseCount, forKey: .responseCount)
            try container.encode(hasSubmitted, forKey: .hasSubmitted)
        }

        private static func date(fromWireTimestamp timestamp: TimeInterval) -> Date {
            // APNs Live Activity payloads use Unix seconds. Older locally created
            // activities used Date's synthesized Codable representation, whose
            // epoch is 2001, so retain compatibility while those activities age out.
            if timestamp >= 1_000_000_000 {
                return Date(timeIntervalSince1970: timestamp)
            }
            return Date(timeIntervalSinceReferenceDate: timestamp)
        }
    }

    let promptID: UUID
    let circleName: String
}
