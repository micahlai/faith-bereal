#if DEBUG
import Foundation

/// Explicit local-only fixtures. Never constructs a hosted client or authorizes a
/// real Apple deletion. The synthetic confirmation is only offered for this type.
actor SafetyUITestService: AccountSafetyProviding {
    private var failures: Set<String>
    private var blocks: Set<UUID> = []
    private var requested = false
    private let completed: Bool

    init(failures: Set<String> = [], completed: Bool = false) {
        self.failures = failures
        self.completed = completed
    }

    private func failOnce(_ operation: String) throws {
        if failures.remove(operation) != nil { throw URLError(.notConnectedToInternet) }
    }

    func requestDeletion(appleCode: String, receipt: String) async throws {
        try failOnce("deletion")
        requested = true
    }
    func receiptStatus(_ receipt: String) async throws -> String {
        try failOnce("receipt")
        return completed ? "completed" : "pending"
    }
    func deletionStatus() async throws -> String { requested ? "pending" : "none" }
    func setBlock(userID: UUID, blocked: Bool) async throws {
        try failOnce(blocked ? "block" : "unblock")
        if blocked { blocks.insert(userID) } else { blocks.remove(userID) }
    }
    func blockedUsers() async throws -> [BlockedUser] {
        try failOnce("load")
        return blocks.sorted { $0.uuidString < $1.uuidString }.map {
            BlockedUser(user_id: $0, display_name: $0.uuidString.hasSuffix("2") ? "Ava" : "Ben")
        }
    }
    func report(blessingID: UUID?, responseID: UUID?, reason: String, detail: String) async throws {
        try failOnce("report")
        guard (blessingID != nil) != (responseID != nil), !reason.isEmpty else {
            throw URLError(.badURL)
        }
    }
}

actor SafetyUITestAuthentication: AuthenticationProviding {
    private var signedIn = true
    private var failSignOut: Bool
    init(failSignOut: Bool = false) { self.failSignOut = failSignOut }
    func cachedUserID() async -> UUID? { signedIn ? UUID(uuidString: "A0000000-0000-0000-0000-000000000001") : nil }
    func currentUserID() async -> UUID? { await cachedUserID() }
    func hasSession() async -> Bool { signedIn }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws { signedIn = true }
    func signOut() async throws {
        if failSignOut { failSignOut = false; throw URLError(.notConnectedToInternet) }
        signedIn = false
    }
}
#endif
