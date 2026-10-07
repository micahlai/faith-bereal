import ActivityKit
import Foundation

enum PromptActivityCountdown {
    static func interval(now: Date, endsAt: Date) -> ClosedRange<Date> {
        now...max(now, endsAt)
    }
}

enum PromptActivityDismissal {
    static let gracePeriod: TimeInterval = 3 * 60

    static func date(after eventDate: Date) -> Date {
        eventDate.addingTimeInterval(gracePeriod)
    }
}

struct PromptActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endsAt: Date
        let responseCount: Int
        let hasSubmitted: Bool
        let allowsLateBlessings: Bool
        let dismissesAt: Date?

        private enum CodingKeys: String, CodingKey {
            case endsAt
            case responseCount
            case hasSubmitted
            case allowsLateBlessings
            case dismissesAt
        }

        init(
            endsAt: Date,
            responseCount: Int,
            hasSubmitted: Bool,
            allowsLateBlessings: Bool = false,
            dismissesAt: Date? = nil
        ) {
            self.endsAt = endsAt
            self.responseCount = responseCount
            self.hasSubmitted = hasSubmitted
            self.allowsLateBlessings = allowsLateBlessings
            self.dismissesAt = dismissesAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawEndsAt = try container.decode(Double.self, forKey: .endsAt)
            endsAt = Self.date(fromWireTimestamp: rawEndsAt)
            responseCount = try container.decode(Int.self, forKey: .responseCount)
            hasSubmitted = try container.decode(Bool.self, forKey: .hasSubmitted)
            allowsLateBlessings = try container.decodeIfPresent(Bool.self, forKey: .allowsLateBlessings) ?? false
            dismissesAt = try container.decodeIfPresent(Double.self, forKey: .dismissesAt)
                .map(Self.date(fromWireTimestamp:))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(endsAt.timeIntervalSince1970, forKey: .endsAt)
            try container.encode(responseCount, forKey: .responseCount)
            try container.encode(hasSubmitted, forKey: .hasSubmitted)
            try container.encode(allowsLateBlessings, forKey: .allowsLateBlessings)
            try container.encodeIfPresent(dismissesAt?.timeIntervalSince1970, forKey: .dismissesAt)
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
