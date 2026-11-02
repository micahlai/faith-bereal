import Foundation

struct RetentionPage: Sendable {
    let blessings: [Blessing]
    let nextAfterID: UUID?
}

struct ExpiringBlessing: Identifiable, Sendable {
    let blessing: Blessing
    let memberName: String
    let circleName: String
    let expiresAt: Date
    var id: UUID { blessing.id }
}

struct LocalArchiveUsage: Sendable {
    let bytes: Int64
    let blessingCount: Int
}
