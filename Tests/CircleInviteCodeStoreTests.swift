import XCTest
@testable import BlessingCircle

final class CircleInviteCodeStoreTests: XCTestCase {
    func testCodeSurvivesStoreRecreationAndIsAccountAndCircleIsolated() throws {
        let suite = "manna-invite-test-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let account = UUID(), circle = UUID()
        let first = CircleInviteCodeStore(suiteName: suite)
        first.set("grace8", accountID: account, circleID: circle)
        let relaunched = CircleInviteCodeStore(suiteName: suite)
        XCTAssertEqual(relaunched.code(accountID: account, circleID: circle), "GRACE8")
        XCTAssertNil(relaunched.code(accountID: UUID(), circleID: circle))
        XCTAssertNil(relaunched.code(accountID: account, circleID: UUID()))
        relaunched.set("NEW123", accountID: account, circleID: circle)
        XCTAssertEqual(first.code(accountID: account, circleID: circle), "NEW123")
        relaunched.set(nil, accountID: account, circleID: circle)
        XCTAssertNil(first.code(accountID: account, circleID: circle))
    }
}
