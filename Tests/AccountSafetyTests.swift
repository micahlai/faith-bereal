import XCTest
@testable import BlessingCircle

@MainActor
final class AccountSafetyTests: XCTestCase {
    private func model(safety: SafetyStub, authentication: (any AuthenticationProviding)? = nil, pending: Bool = false) -> (AppModel, UserDefaults) {
        let suite = "AccountSafetyTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set(pending, forKey: "privacy.deletionPending")
        preferences.set("test-receipt", forKey: "privacy.deletionReceipt")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        return (AppModel(repository: LocalBlessingRepository(), authentication: authentication,
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("draft")),
            accountSafety: safety, deletionPreferences: preferences,
            metadataStore: CircleMetadataStore(directory: root.appendingPathComponent("metadata")),
            identityPhotoCache: IdentityPhotoCache(directory: root.appendingPathComponent("photos")),
            registersForRemoteNotifications: false, runsBackgroundRefreshes: false), preferences)
    }

    func testRejectedDeletionLeavesAccessAndDoesNotPersistAcceptance() async {
        let (model, preferences) = model(safety: SafetyStub(rejectRequest: true))
        await model.bootstrap()
        let account = model.currentUser?.id
        XCTAssertNotNil(account)
        await model.requestAccountDeletion(appleCode: "synthetic-code")
        XCTAssertFalse(model.accountDeletionPending)
        XCTAssertFalse(preferences.bool(forKey: "privacy.deletionPending"))
        XCTAssertEqual(model.currentUser?.id, account)
        XCTAssertNotNil(model.circle)
        XCTAssertFalse(model.isDeletingAccount)
        XCTAssertTrue(model.accountDeletionRequestError?.contains("may already be queued") == true)
    }

    func testAcceptedDeletionPersistsGateAndClearsCurrentContent() async {
        let (model, preferences) = model(safety: SafetyStub())
        await model.bootstrap()
        XCTAssertFalse(model.circles.isEmpty)
        await model.requestAccountDeletion(appleCode: "synthetic-code")
        XCTAssertTrue(model.accountDeletionPending)
        XCTAssertTrue(preferences.bool(forKey: "privacy.deletionPending"))
        XCTAssertTrue(model.circles.isEmpty)
        XCTAssertTrue(model.lanes.isEmpty)
        XCTAssertNil(model.circle)
        XCTAssertNil(model.prompt)
        XCTAssertFalse(model.isDeletingAccount)
    }

    func testStatusFailureAndPendingNeverClaimCompletionThenVerifiedCompletionDoes() async {
        let safety = SafetyStub(failStatus: true)
        let (model, _) = model(safety: safety, pending: true)
        await model.checkAccountDeletion()
        XCTAssertEqual(model.accountDeletionStatusMessage, "Status is unavailable. Try again or contact support.")
        await model.checkAccountDeletion()
        XCTAssertTrue(model.accountDeletionStatusMessage?.contains("has not been confirmed complete") == true)
        await safety.complete()
        await model.checkAccountDeletion()
        XCTAssertTrue(model.accountDeletionStatusMessage?.hasPrefix("Deletion completed in the active service") == true)
        XCTAssertTrue(model.accountDeletionPending, "Completion keeps normal content inaccessible until sign-out")
    }

    func testFailedSignOutKeepsDeletionGateAndSuccessfulRetryClearsIt() async {
        let (model, preferences) = model(safety: SafetyStub(), authentication: SignOutStub(), pending: true)
        await model.signOut()
        XCTAssertTrue(model.accountDeletionPending)
        XCTAssertTrue(preferences.bool(forKey: "privacy.deletionPending"))
        XCTAssertNotNil(model.message)
        await model.signOut()
        XCTAssertFalse(model.accountDeletionPending)
        XCTAssertFalse(preferences.bool(forKey: "privacy.deletionPending"))
        XCTAssertEqual(model.loadState, .signedOut)
    }
}

private actor SafetyStub: AccountSafetyProviding {
    let rejectRequest: Bool
    var failStatus: Bool
    var completed = false
    init(rejectRequest: Bool = false, failStatus: Bool = false) { self.rejectRequest = rejectRequest; self.failStatus = failStatus }
    func requestDeletion(appleCode: String, receipt: String) async throws {
        if rejectRequest { throw URLError(.notConnectedToInternet) }
    }
    func receiptStatus(_ receipt: String) async throws -> String {
        if failStatus { failStatus = false; throw URLError(.notConnectedToInternet) }
        return completed ? "completed" : "pending"
    }
    func complete() { completed = true }
    func deletionStatus() async throws -> String { "none" }
    func setBlock(userID: UUID, blocked: Bool) async throws {}
    func blockedUsers() async throws -> [BlockedUser] { [] }
    func report(blessingID: UUID?, responseID: UUID?, reason: String, detail: String) async throws {}
}

private actor SignOutStub: AuthenticationProviding {
    var shouldFail = true
    func hasSession() async -> Bool { true }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {}
    func signOut() async throws {
        if shouldFail { shouldFail = false; throw URLError(.notConnectedToInternet) }
    }
}
