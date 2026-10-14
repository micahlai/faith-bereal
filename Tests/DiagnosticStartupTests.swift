import XCTest
@testable import BlessingCircle

final class DiagnosticStartupTests: XCTestCase {
    @MainActor
    func testRestoredAccountCollectsSessionFailureBeforeRepositoryBootstrap() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StartupDiagnostics-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let accountID = UUID()
        let store = BackendDiagnosticStore(root: root)
        _ = try await store.setConsent(accountID: accountID, enabled: true)
        let collection = DiagnosticCollectionController(store: store, buildNumber: 32)
        defer { collection.deactivate() }
        let model = AppModel(repository: LocalBlessingRepository(),
            authentication: FailingStartupAuthentication(accountID: accountID), diagnosticCollection: collection)

        await model.bootstrap()

        for _ in 0..<100 {
            if try await store.load(accountID: accountID).queuedCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let report = try await store.prepareReport(accountID: accountID)
        let events = try XCTUnwrap(report).events
        XCTAssertTrue(events.contains { $0.requestKind == .auth && $0.outcome == .failure
            && $0.transportErrorCode == NSURLErrorCannotConnectToHost })
        XCTAssertTrue(events.contains { $0.stage == .bootstrapVisible && $0.outcome == .failure })
        XCTAssertNil(model.currentUser, "Cached identity must not authorize a user or expose content")
        XCTAssertEqual(model.loadState, .signedOut)
    }
}

private actor FailingStartupAuthentication: AuthenticationProviding {
    let accountID: UUID
    init(accountID: UUID) { self.accountID = accountID }
    func cachedUserID() async -> UUID? { accountID }
    func hasSession() async -> Bool {
        BackendDiagnostics.shared.beginRequest(.auth).finish(error: URLError(.cannotConnectToHost))
        return false
    }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws { }
    func signOut() async throws { }
}
