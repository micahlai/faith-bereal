import XCTest
@testable import BlessingCircle

final class DiagnosticCollectionTests: XCTestCase {
    func testCollectionDefaultsOffAndConsentSurvivesStoreRecreation() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), other = UUID()
        let store = BackendDiagnosticStore(root: root)
        let initial = try await store.load(accountID: account)
        XCTAssertFalse(initial.isEnabled)
        XCTAssertEqual(initial.queuedCount, 0)
        _ = try await store.setConsent(accountID: account, enabled: true)
        let recreated = BackendDiagnosticStore(root: root)
        let restored = try await recreated.load(accountID: account)
        let isolated = try await recreated.load(accountID: other)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertFalse(isolated.isEnabled)
        XCTAssertEqual(isolated.queuedCount, 0)
    }

    func testPendingRecordsAndRetryPayloadSurviveRelaunch() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let consent = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(consent.sessionID)
        try await store.append(accountID: account, sessionID: session, buildNumber: 31, event: event(now), now: now)
        try await store.checkpoint()
        let recreated = BackendDiagnosticStore(root: root)
        let loaded = try await recreated.load(accountID: account, now: now)
        XCTAssertEqual(loaded.queuedCount, 1)
        let firstOptional = try await recreated.prepareReport(accountID: account, now: now)
        let first = try XCTUnwrap(firstOptional)
        let relaunched = BackendDiagnosticStore(root: root)
        let retryOptional = try await relaunched.prepareReport(accountID: account, now: now)
        let retry = try XCTUnwrap(retryOptional)
        XCTAssertEqual(first.reportID, retry.reportID)
        XCTAssertEqual(first.sessionID, retry.sessionID)
        XCTAssertEqual(first.buildNumber, retry.buildNumber)
        XCTAssertEqual(try encoded(first), try encoded(retry))
        let ignored = try await relaunched.acknowledge(accountID: account, reportID: UUID(), now: now)
        XCTAssertEqual(ignored.queuedCount, 1)
        XCTAssertNil(ignored.lastUploadedAt)
        let accepted = try await relaunched.acknowledge(accountID: account, reportID: first.reportID, now: now)
        XCTAssertEqual(accepted.queuedCount, 0)
        XCTAssertEqual(accepted.lastUploadedAt, now)
    }

    func testQueueIsBoundedIncludingFrozenRetryBatchAndDropsOldestPending() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let consent = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(consent.sessionID)
        for index in 0..<1_000 {
            try await store.append(accountID: account, sessionID: session, buildNumber: 31,
                event: event(now, duration: Double(index)), now: now)
        }
        let firstOptional = try await store.prepareReport(accountID: account, now: now)
        let first = try XCTUnwrap(firstOptional)
        XCTAssertEqual(first.events.count, 100)
        for index in 1_000..<1_150 {
            try await store.append(accountID: account, sessionID: session, buildNumber: 31,
                event: event(now, duration: Double(index)), now: now)
        }
        let snapshot = try await store.load(accountID: account, now: now)
        XCTAssertEqual(snapshot.queuedCount, 1_000)
        let retry = try await store.prepareReport(accountID: account, now: now)
        XCTAssertEqual(retry?.reportID, first.reportID)
        XCTAssertEqual(retry?.events.first?.durationMilliseconds, 0)
        _ = try await store.acknowledge(accountID: account, reportID: first.reportID, now: now)
        let next = try await store.prepareReport(accountID: account, now: now)
        XCTAssertEqual(next?.events.count, 100)
        XCTAssertEqual(next?.events.first?.durationMilliseconds, 250)
    }

    func testOptOutDropsPendingAndPreparedReportsAndRejectsDelayedEvents() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let consent = try await store.setConsent(accountID: account, enabled: true, now: now)
        let oldSession = try XCTUnwrap(consent.sessionID)
        try await store.append(accountID: account, sessionID: oldSession, buildNumber: 31, event: event(now), now: now)
        _ = try await store.prepareReport(accountID: account, now: now)
        _ = try await store.setConsent(accountID: account, enabled: false, now: now)
        try await store.append(accountID: account, sessionID: oldSession, buildNumber: 31, event: event(now), now: now)
        let disabled = try await store.load(accountID: account, now: now)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(disabled.queuedCount, 0)
        let recreated = BackendDiagnosticStore(root: root)
        let restored = try await recreated.load(accountID: account, now: now)
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.queuedCount, 0)
        _ = try await recreated.setConsent(accountID: account, enabled: true, now: now)
        try await recreated.append(accountID: account, sessionID: oldSession, buildNumber: 31, event: event(now), now: now)
        let empty = try await recreated.prepareReport(accountID: account, now: now)
        XCTAssertNil(empty)
    }

    func testBatchesNeverMixAccountsSessionsOrBuilds() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), other = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let firstConsent = try await store.setConsent(accountID: account, enabled: true, now: now)
        let firstSession = try XCTUnwrap(firstConsent.sessionID)
        try await store.append(accountID: account, sessionID: firstSession, buildNumber: 31, event: event(now, duration: 1), now: now)
        let secondConsent = try await store.beginSession(accountID: account, now: now)
        let secondSession = try XCTUnwrap(secondConsent.sessionID)
        try await store.append(accountID: account, sessionID: firstSession, buildNumber: 31, event: event(now, duration: 99), now: now)
        try await store.append(accountID: account, sessionID: secondSession, buildNumber: 32, event: event(now, duration: 2), now: now)
        let otherConsent = try await store.setConsent(accountID: other, enabled: true, now: now)
        try await store.append(accountID: other, sessionID: XCTUnwrap(otherConsent.sessionID), buildNumber: 31, event: event(now, duration: 3), now: now)
        let firstOptional = try await store.prepareReport(accountID: account, now: now)
        let first = try XCTUnwrap(firstOptional)
        XCTAssertEqual(first.sessionID, firstSession)
        XCTAssertEqual(first.buildNumber, 31)
        XCTAssertEqual(first.events.map(\.durationMilliseconds), [1])
        _ = try await store.acknowledge(accountID: account, reportID: first.reportID, now: now)
        let second = try await store.prepareReport(accountID: account, now: now)
        let third = try await store.prepareReport(accountID: other, now: now)
        XCTAssertEqual(second?.sessionID, secondSession)
        XCTAssertEqual(second?.buildNumber, 32)
        XCTAssertEqual(second?.events.map(\.durationMilliseconds), [2])
        XCTAssertEqual(third?.events.map(\.durationMilliseconds), [3])
    }

    func testStaleFrozenBatchExpiresBeforeServerFourteenDayLimit() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let consent = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(consent.sessionID)
        try await store.append(accountID: account, sessionID: session, buildNumber: 31, event: event(now), now: now)
        _ = try await store.prepareReport(accountID: account, now: now)
        let later = now.addingTimeInterval(BackendDiagnosticStore.localLifetime + 1)
        try await store.append(accountID: account, sessionID: session, buildNumber: 31, event: event(later, duration: 2), now: later)
        let current = try await store.prepareReport(accountID: account, now: later)
        XCTAssertEqual(current?.events.map(\.durationMilliseconds), [2])
    }

    func testInvalidClockDurationAndSizeNeverPoisonUploadQueue() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let consent = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(consent.sessionID)
        let invalid = [event(now.addingTimeInterval(-14 * 86_400)), event(now.addingTimeInterval(301)),
            event(now, duration: nil), event(now, duration: -.infinity), event(now, duration: .nan),
            event(now, duration: -1), event(now, duration: 3_600_001),
            event(now, payload: -1), event(now, payload: 1_073_741_825),
            event(now, status: 99), event(now, status: 600),
            event(now, transport: 1), event(now, transport: -200_001),
            BackendDiagnostics.Event(kind: .stage, startedAt: now, durationMilliseconds: 1,
                stage: .submit, requestKind: .rpc, outcome: .success, httpStatus: nil,
                transportErrorCode: nil, payloadBytes: nil, receivedBytes: nil)]
        for value in invalid {
            try await store.append(accountID: account, sessionID: session, buildNumber: 31, event: value, now: now)
        }
        try await store.append(accountID: account, sessionID: session, buildNumber: 0, event: event(now), now: now)
        try await store.append(accountID: account, sessionID: session, buildNumber: 31, event: event(now), now: now)
        let report = try await store.prepareReport(accountID: account, now: now)
        XCTAssertEqual(report?.events.count, 1)
    }

    @MainActor
    func testFailedUploadRetriesSameReportAndManualAttemptsAreSpaced() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let uploader = DiagnosticTestUploader(failuresRemaining: 1)
        let controller = DiagnosticCollectionController(store: store, uploader: uploader,
            diagnostics: BackendDiagnostics(enabled: false), buildNumber: 31)
        defer { controller.deactivate() }
        await controller.activate(accountID: account)
        await controller.setEnabled(true)
        try await append(to: store, account: account, at: now)
        await controller.sendNow(now: now)
        await controller.refreshSummary()
        XCTAssertEqual(controller.queuedCount, 1)
        XCTAssertNil(controller.lastUploadedAt)
        await controller.sendNow(now: now.addingTimeInterval(59))
        let attemptsBeforeRetry = await uploader.reports
        XCTAssertEqual(attemptsBeforeRetry.count, 1)
        await controller.sendNow(now: now.addingTimeInterval(60))
        let attempts = await uploader.reports
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0].reportID, attempts[1].reportID)
        XCTAssertEqual(try encoded(attempts[0]), try encoded(attempts[1]))
        XCTAssertEqual(controller.queuedCount, 0)
        XCTAssertNotNil(controller.lastUploadedAt)
    }

    @MainActor
    func testOptOutDuringSuspendedUploadCannotRestoreQueueOrSuccess() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let uploader = SuspendedDiagnosticUploader()
        let controller = DiagnosticCollectionController(store: store, uploader: uploader,
            diagnostics: BackendDiagnostics(enabled: false), buildNumber: 31)
        defer { controller.deactivate() }
        await controller.activate(accountID: account)
        await controller.setEnabled(true)
        try await append(to: store, account: account, at: now)
        let sending = Task { await controller.sendNow(now: now) }
        let started = await uploader.waitUntilStarted()
        XCTAssertTrue(started, "Upload should reach the suspended test transport")
        XCTAssertTrue(controller.isSending)
        await controller.setEnabled(false)
        await uploader.release()
        await sending.value
        await controller.refreshSummary()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.isSending)
        XCTAssertEqual(controller.queuedCount, 0)
        XCTAssertNil(controller.lastUploadedAt)
        XCTAssertNotEqual(controller.status, "Diagnostic batch sent.")
    }

    @MainActor
    func testAccountChangeDuringUploadCannotAcknowledgeOtherAccount() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), other = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let uploader = SuspendedDiagnosticUploader()
        let controller = DiagnosticCollectionController(store: store, uploader: uploader,
            diagnostics: BackendDiagnostics(enabled: false), buildNumber: 31)
        defer { controller.deactivate() }
        await controller.activate(accountID: account)
        await controller.setEnabled(true)
        try await append(to: store, account: account, at: now)
        let sending = Task { await controller.sendNow(now: now) }
        let started = await uploader.waitUntilStarted()
        XCTAssertTrue(started, "Upload should reach the suspended test transport")
        await controller.activate(accountID: other)
        await controller.setEnabled(true)
        try await append(to: store, account: other, at: now)
        await uploader.release()
        await sending.value
        await controller.refreshSummary()
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.queuedCount, 1)
        XCTAssertNil(controller.lastUploadedAt)
        let previous = try await store.load(accountID: account, now: now)
        XCTAssertEqual(previous.queuedCount, 1, "An ambiguous in-flight success retains its stable retry report")
        let sentAccount = await uploader.accountID
        XCTAssertEqual(sentAccount, account)
    }

    func testSpansKeepOriginalCaptureSinkAcrossAccountChanges() {
        let diagnostics = BackendDiagnostics(enabled: false)
        let firstAccount = CollectionEventRecorder(), nextAccount = CollectionEventRecorder()
        diagnostics.setCollectionSink(firstAccount.append)
        let stage = diagnostics.begin(.circleRefresh)
        let request = diagnostics.beginRequest(.blessings)
        diagnostics.setCollectionSink(nextAccount.append)
        stage.finish(.success)
        request.finish(httpStatus: 200)
        XCTAssertEqual(firstAccount.count, 2)
        XCTAssertEqual(nextAccount.count, 0)
        diagnostics.begin(.circleRefresh).finish(.success)
        XCTAssertEqual(nextAccount.count, 1)
    }

    func testOperationsStartedBeforeConsentAreNeverCollectedRetroactively() {
        let diagnostics = BackendDiagnostics(enabled: false)
        let stage = diagnostics.begin(.bootstrapVisible)
        let request = diagnostics.beginRequest(.profiles)
        let recorder = CollectionEventRecorder()
        diagnostics.setCollectionSink(recorder.append)
        stage.finish(.success)
        request.finish(httpStatus: 200)
        XCTAssertEqual(recorder.count, 0)
    }

    func testDelayedEndSessionCannotStopNewSessionOfSameAccount() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let first = try await store.setConsent(accountID: account, enabled: true, now: now)
        let second = try await store.beginSession(accountID: account, now: now)
        try await store.endSession(accountID: account, sessionID: XCTUnwrap(first.sessionID))
        try await store.append(accountID: account, sessionID: XCTUnwrap(second.sessionID),
            buildNumber: 31, event: event(now), now: now)
        let snapshot = try await store.load(accountID: account, now: now)
        XCTAssertEqual(snapshot.sessionID, second.sessionID)
        XCTAssertEqual(snapshot.queuedCount, 1)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticCollection-\(UUID())", isDirectory: true)
    }

    private func event(_ date: Date, duration: Double? = 10, payload: Int64? = nil,
        status: Int? = 200, transport: Int? = nil) -> BackendDiagnostics.Event {
        .init(kind: .request, startedAt: date, durationMilliseconds: duration, stage: nil,
            requestKind: .blessings, outcome: .success, httpStatus: status,
            transportErrorCode: transport, payloadBytes: payload, receivedBytes: 20)
    }

    @MainActor
    private func append(to store: BackendDiagnosticStore, account: UUID, at now: Date) async throws {
        let snapshot = try await store.load(accountID: account, now: now)
        try await store.append(accountID: account, sessionID: XCTUnwrap(snapshot.sessionID),
            buildNumber: 31, event: event(now), now: now)
    }

    private func encoded(_ report: BackendDiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}

private final class CollectionEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [BackendDiagnostics.Event] = []
    var count: Int { lock.withLock { events.count } }
    func append(_ event: BackendDiagnostics.Event) { lock.withLock { events.append(event) } }
}

private actor DiagnosticTestUploader: BackendDiagnosticUploading {
    private(set) var reports: [BackendDiagnosticReport] = []
    var failuresRemaining: Int
    init(failuresRemaining: Int) { self.failuresRemaining = failuresRemaining }
    func upload(_ report: BackendDiagnosticReport, accountID: UUID) async throws {
        reports.append(report)
        if failuresRemaining > 0 { failuresRemaining -= 1; throw URLError(.notConnectedToInternet) }
    }
}

/// Intentionally ignores cancellation so controller fencing is tested even when
/// a server acceptance arrives after local consent/account state has changed.
private actor SuspendedDiagnosticUploader: BackendDiagnosticUploading {
    private var completion: CheckedContinuation<Void, Never>?
    private(set) var accountID: UUID?

    func upload(_ report: BackendDiagnosticReport, accountID: UUID) async throws {
        self.accountID = accountID
        await withCheckedContinuation { continuation in
            completion = continuation
        }
    }

    func waitUntilStarted() async -> Bool {
        for _ in 0..<150 {
            if completion != nil { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    func release() {
        completion?.resume()
        completion = nil
    }
}
