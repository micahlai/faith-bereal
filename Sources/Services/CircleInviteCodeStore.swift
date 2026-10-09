import Foundation

// Stable, account-isolated keys survive an in-place app update. These are only
// hints: the server verifies every cached code against its current hash.
struct CircleInviteCodeStore: Sendable {
    var suiteName: String? = nil

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private func key(accountID: UUID, circleID: UUID) -> String {
        "circle.invite.\(accountID.uuidString.lowercased()).\(circleID.uuidString.lowercased())"
    }

    func code(accountID: UUID, circleID: UUID) -> String? {
        defaults.string(forKey: key(accountID: accountID, circleID: circleID))
            .flatMap(CircleInviteLink.normalize(code:))
    }

    func set(_ code: String?, accountID: UUID, circleID: UUID) {
        let key = key(accountID: accountID, circleID: circleID)
        if let code = code.flatMap(CircleInviteLink.normalize(code:)) {
            defaults.set(code, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
