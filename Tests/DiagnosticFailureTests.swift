import XCTest
import Supabase
@testable import BlessingCircle

final class DiagnosticFailureTests: XCTestCase {
    func testPostgrestConnectionLimitsKeepOnlySanitizedCodeAndCategory() throws {
        for code in ["53300", "PGRST003"] {
            let error = PostgrestError(detail: "private-account private-token", hint: "private-blessing",
                code: code, message: "private-response")
            let failure = BackendDiagnosticFailure.capture(error: error)
            XCTAssertEqual(failure.source, .postgrest)
            XCTAssertEqual(failure.code, code)
            XCTAssertEqual(failure.category, .connectionLimit)
            let event = try capturedEvent(error: error)
            XCTAssertEqual(event.errorSource, .postgrest)
            XCTAssertEqual(event.errorCode, code)
            XCTAssertEqual(event.errorCategory, .connectionLimit)
            try assertPrivateValuesAbsent(event)
        }
    }

    func testConnectionLimitMessageIsClassifiedWithoutSerializingMessage() throws {
        let error = PostgrestError(message: "Too many connections for private-account at https://private.invalid/private-token")
        let failure = BackendDiagnosticFailure.capture(error: error)
        XCTAssertEqual(failure.source, .postgrest)
        XCTAssertNil(failure.code)
        XCTAssertEqual(failure.category, .connectionLimit)
        let event = try capturedEvent(error: error)
        try assertPrivateValuesAbsent(event)
        XCTAssertFalse(try serialized(event).lowercased().contains("too many connections"))
    }

    func testArbitraryPostgrestCodeCannotLeakResponseContent() throws {
        let error = PostgrestError(code: "private-token https://private.invalid", message: "private-response")
        let failure = BackendDiagnosticFailure.capture(error: error)
        XCTAssertEqual(failure.source, .postgrest)
        XCTAssertNil(failure.code)
        XCTAssertEqual(failure.category, .other)
        try assertPrivateValuesAbsent(capturedEvent(error: error))
    }

    func testSpeechAndAudioDomainsKeepNumericCodeWithoutPrivateUserInfo() throws {
        for (domain, expectedSource) in [
            ("kAFAssistantErrorDomain", BackendErrorSource.speech),
            ("kLSRErrorDomain", .speech),
            ("AVFAudioErrorDomain", .audio),
            ("NSOSStatusErrorDomain", .audio)
        ] {
            let error = NSError(domain: domain, code: 1101, userInfo: [
                NSLocalizedDescriptionKey: "private-response private-token",
                NSUnderlyingErrorKey: NSError(domain: "private-account", code: 99)
            ])
            let failure = BackendDiagnosticFailure.capture(error: error)
            XCTAssertEqual(failure.source, expectedSource, domain)
            XCTAssertEqual(failure.code, "1101", domain)
            XCTAssertEqual(failure.category, .other)
            try assertPrivateValuesAbsent(capturedEvent(error: error))
        }
    }

    func testUnknownNSErrorDomainAndCodeAreNotUploaded() throws {
        let error = NSError(domain: "private-account/private-token", code: 92741,
            userInfo: [NSLocalizedDescriptionKey: "private-response"])
        let failure = BackendDiagnosticFailure.capture(error: error)
        XCTAssertEqual(failure.source, .other)
        XCTAssertNil(failure.code)
        XCTAssertEqual(failure.category, .other)
        let event = try capturedEvent(error: error)
        try assertPrivateValuesAbsent(event)
        XCTAssertFalse(try serialized(event).contains("92741"))
    }

    func testURLFailureKeepsExistingTransportCodeAndClosedSource() throws {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "https://private.invalid/private-token"])
        let recorder = FailureEventRecorder()
        let diagnostics = BackendDiagnostics(enabled: true, sink: recorder.append)
        diagnostics.beginRequest(.rpc).finish(error: error)
        let event = try XCTUnwrap(recorder.events.first)
        XCTAssertEqual(event.errorSource, .url)
        XCTAssertEqual(event.transportErrorCode, NSURLErrorCannotConnectToHost)
        XCTAssertEqual(event.outcome, .failure)
        try assertPrivateValuesAbsent(event)
    }

    func testStorageAndAuthErrorsAreRecognizedWithoutUploadingTheirDescriptions() throws {
        let errors: [(any Error, BackendErrorSource)] = [
            (StorageError(statusCode: "503", message: "private-response private-token", error: "private-account"), .storage),
            (AuthError.sessionMissing, .auth)
        ]
        for (error, source) in errors {
            let failure = BackendDiagnosticFailure.capture(error: error)
            XCTAssertEqual(failure.source, source)
            try assertPrivateValuesAbsent(capturedEvent(error: error))
        }
    }

    func testExplicitCaptureFailureIsSingleTimestampedZeroDurationRequest() throws {
        let recorder = FailureEventRecorder()
        let diagnostics = BackendDiagnostics(enabled: true, sink: recorder.append)
        let before = Date()
        diagnostics.recordFailure(.speech, error: NSError(domain: "kAFAssistantErrorDomain", code: 1101))
        let after = Date()
        let event = try XCTUnwrap(recorder.events.first)
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(event.kind, .request)
        XCTAssertEqual(event.requestKind, .speech)
        XCTAssertNil(event.stage)
        XCTAssertEqual(event.outcome, .failure)
        XCTAssertEqual(event.durationMilliseconds, 0)
        XCTAssertGreaterThanOrEqual(event.startedAt, before)
        XCTAssertLessThanOrEqual(event.startedAt, after)
        XCTAssertEqual(event.errorSource, .speech)
        XCTAssertEqual(event.errorCode, "1101")
    }

    func testPreclassifiedFailuresAndDisabledDiagnosticsRespectCollectionGate() throws {
        let recorder = FailureEventRecorder()
        let diagnostics = BackendDiagnostics(enabled: false, sink: recorder.append)
        let failure = BackendDiagnosticFailure.capture(error: NSError(domain: "AVFAudioErrorDomain", code: -50))
        diagnostics.recordFailure(.audio, failure: failure)
        XCTAssertTrue(recorder.events.isEmpty)
        diagnostics.setCollectionSink(recorder.append)
        diagnostics.recordFailure(.audio, failure: failure)
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events.first?.errorSource, .audio)
        XCTAssertEqual(recorder.events.first?.errorCode, "-50")
        diagnostics.setCollectionSink(nil)
    }

    func testExplicitCancellationIsNeverReportedAsCaptureFailure() {
        let recorder = FailureEventRecorder()
        let diagnostics = BackendDiagnostics(enabled: true, sink: recorder.append)
        diagnostics.recordFailure(.speech, error: CancellationError())
        diagnostics.recordFailure(.audio, error: URLError(.cancelled))
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testBuild33EventWithoutErrorFieldsStillDecodes() throws {
        let legacy: [String: Any] = [
            "kind": "request", "startedAt": "2026-10-15T06:00:00Z",
            "durationMilliseconds": 12.5, "requestKind": "rpc", "outcome": "failure"
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(BackendDiagnostics.Event.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(event.outcome, .failure)
        XCTAssertNil(event.errorSource)
        XCTAssertNil(event.errorCode)
        XCTAssertNil(event.errorCategory)
    }

    func testNewFailureOvertakesUnsentSuccessBacklog() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BackendDiagnosticStore(root: root)
        let account = UUID(), now = Date()
        let enabled = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(enabled.sessionID)
        for index in 0..<150 {
            try await store.append(accountID: account, sessionID: session, buildNumber: 34,
                event: event(now, duration: Double(index)), now: now)
        }
        try await store.append(accountID: account, sessionID: session, buildNumber: 34,
            event: event(now, duration: 999, outcome: .failure), now: now)
        let report = try await store.prepareReport(accountID: account, now: now)
        XCTAssertEqual(report?.events.first?.outcome, .failure)
        XCTAssertEqual(report?.events.first?.durationMilliseconds, 999)
        XCTAssertLessThanOrEqual(report?.events.count ?? 0, BackendDiagnosticStore.batchSize)
    }

    func testNewFailureCannotAlterFrozenRetryEvenAcrossRelaunch() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let enabled = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(enabled.sessionID)
        try await store.append(accountID: account, sessionID: session, buildNumber: 33,
            event: event(now, duration: 1), now: now)
        let frozenOptional = try await store.prepareReport(accountID: account, now: now)
        let frozen = try XCTUnwrap(frozenOptional)
        try await store.append(accountID: account, sessionID: session, buildNumber: 34,
            event: event(now, duration: 2, outcome: .failure), now: now)
        try await store.checkpoint()
        let recreated = BackendDiagnosticStore(root: root)
        let retryOptional = try await recreated.prepareReport(accountID: account, now: now)
        let retry = try XCTUnwrap(retryOptional)
        XCTAssertEqual(try encoded(frozen), try encoded(retry))
        _ = try await recreated.acknowledge(accountID: account, reportID: frozen.reportID, now: now)
        let next = try await recreated.prepareReport(accountID: account, now: now)
        XCTAssertEqual(next?.buildNumber, 34)
        XCTAssertEqual(next?.events.first?.outcome, .failure)
        XCTAssertEqual(next?.events.first?.durationMilliseconds, 2)
    }

    func testSuccessFloodDoesNotEvictPendingFailureAtQueueLimit() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let enabled = try await store.setConsent(accountID: account, enabled: true, now: now)
        let session = try XCTUnwrap(enabled.sessionID)
        try await store.append(accountID: account, sessionID: session, buildNumber: 34,
            event: event(now, duration: 9999, outcome: .failure), now: now)
        for index in 0..<(BackendDiagnosticStore.maximumEvents + 50) {
            try await store.append(accountID: account, sessionID: session, buildNumber: 34,
                event: event(now, duration: Double(index)), now: now)
        }
        let snapshot = try await store.load(accountID: account, now: now)
        XCTAssertEqual(snapshot.queuedCount, BackendDiagnosticStore.maximumEvents)
        let report = try await store.prepareReport(accountID: account, now: now)
        XCTAssertEqual(report?.events.first?.outcome, .failure)
        XCTAssertEqual(report?.events.first?.durationMilliseconds, 9999)
    }

    func testFailurePriorityPreservesSessionBuildAndAccountPartition() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), other = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let initial = try await store.setConsent(accountID: account, enabled: true, now: now)
        let initialSession = try XCTUnwrap(initial.sessionID)
        try await store.append(accountID: account, sessionID: initialSession, buildNumber: 33,
            event: event(now, duration: 1), now: now)
        let current = try await store.beginSession(accountID: account, now: now)
        let currentSession = try XCTUnwrap(current.sessionID)
        try await store.append(accountID: account, sessionID: currentSession, buildNumber: 34,
            event: event(now, duration: 2, outcome: .failure), now: now)
        let otherConsent = try await store.setConsent(accountID: other, enabled: true, now: now)
        try await store.append(accountID: other, sessionID: XCTUnwrap(otherConsent.sessionID), buildNumber: 35,
            event: event(now, duration: 3, outcome: .failure), now: now)
        let firstOptional = try await store.prepareReport(accountID: account, now: now)
        let first = try XCTUnwrap(firstOptional)
        XCTAssertEqual(first.sessionID, currentSession)
        XCTAssertEqual(first.buildNumber, 34)
        XCTAssertEqual(first.events.map(\.durationMilliseconds), [2])
        _ = try await store.acknowledge(accountID: account, reportID: first.reportID, now: now)
        let second = try await store.prepareReport(accountID: account, now: now)
        XCTAssertEqual(second?.sessionID, initialSession)
        XCTAssertEqual(second?.buildNumber, 33)
        XCTAssertEqual(second?.events.map(\.durationMilliseconds), [1])
        let isolated = try await store.prepareReport(accountID: other, now: now)
        XCTAssertEqual(isolated?.buildNumber, 35)
        XCTAssertEqual(isolated?.events.map(\.durationMilliseconds), [3])
    }

    @MainActor
    func testUploadOutageIsRecordedOnceAndCannotMutateItsOwnRetry() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let uploader = FailureDiagnosticUploader(failures: 2,
            error: PostgrestError(code: "53300", message: "private-response private-token"))
        let controller = DiagnosticCollectionController(store: store, uploader: uploader,
            diagnostics: BackendDiagnostics(enabled: false), buildNumber: 34)
        defer { controller.deactivate() }
        await controller.activate(accountID: account)
        controller.setForeground(false)
        await controller.setEnabled(true)
        let active = try await store.load(accountID: account, now: now)
        try await store.append(accountID: account, sessionID: XCTUnwrap(active.sessionID), buildNumber: 34,
            event: event(now, duration: 1), now: now)
        await sendManualBatch(controller, now: now)
        await sendManualBatch(controller, now: now.addingTimeInterval(60))
        let pending = try await store.load(accountID: account, now: now)
        XCTAssertEqual(pending.queuedCount, 2, "Repeated outage retries add only one failure behind the frozen report")
        await sendManualBatch(controller, now: now.addingTimeInterval(120))
        await sendManualBatch(controller, now: now.addingTimeInterval(180))
        let reports = await uploader.reports
        XCTAssertEqual(reports.count, 4)
        XCTAssertEqual(try encoded(reports[0]), try encoded(reports[1]))
        XCTAssertEqual(try encoded(reports[0]), try encoded(reports[2]))
        let uploadFailure = try XCTUnwrap(reports.last?.events.first)
        XCTAssertEqual(uploadFailure.requestKind, .diagnosticsUpload)
        XCTAssertEqual(uploadFailure.errorSource, .postgrest)
        XCTAssertEqual(uploadFailure.errorCode, "53300")
        XCTAssertEqual(uploadFailure.errorCategory, .connectionLimit)
        try assertPrivateValuesAbsent(uploadFailure)
        let drained = try await store.load(accountID: account, now: now.addingTimeInterval(180))
        XCTAssertEqual(drained.queuedCount, 0)
    }

    @MainActor
    func testCancelledUploadDoesNotCreateFalseDiagnosticFailure() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), now = Date()
        let store = BackendDiagnosticStore(root: root)
        let uploader = FailureDiagnosticUploader(failures: 1, error: URLError(.cancelled))
        let controller = DiagnosticCollectionController(store: store, uploader: uploader,
            diagnostics: BackendDiagnostics(enabled: false), buildNumber: 34)
        defer { controller.deactivate() }
        await controller.activate(accountID: account)
        controller.setForeground(false)
        await controller.setEnabled(true)
        let active = try await store.load(accountID: account, now: now)
        try await store.append(accountID: account, sessionID: XCTUnwrap(active.sessionID), buildNumber: 34,
            event: event(now, duration: 1), now: now)
        await sendManualBatch(controller, now: now)
        let pending = try await store.load(accountID: account, now: now)
        XCTAssertEqual(pending.queuedCount, 1, "Cancellation keeps the original retry without inventing an outage")
    }

    @MainActor
    func testForegroundCaptureFailureStartsUploadWithoutWaitingForPeriodicWorker() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let uploader = FailureDiagnosticUploader(failures: 0, error: URLError(.cannotConnectToHost))
        let diagnostics = BackendDiagnostics(enabled: false)
        let controller = DiagnosticCollectionController(store: BackendDiagnosticStore(root: root), uploader: uploader,
            diagnostics: diagnostics, buildNumber: 34)
        defer { controller.deactivate() }
        await controller.activate(accountID: UUID())
        await controller.setEnabled(true)
        diagnostics.recordFailure(.speech, error: NSError(domain: "kAFAssistantErrorDomain", code: 1101))
        let uploaded = await uploader.waitForCount(1)
        XCTAssertTrue(uploaded, "A newly captured failure should trigger a foreground attempt within seconds")
        let reports = await uploader.reports
        let event = try XCTUnwrap(reports.first?.events.first)
        XCTAssertEqual(event.requestKind, .speech)
        XCTAssertEqual(event.errorSource, .speech)
        XCTAssertEqual(event.errorCode, "1101")
    }

    @MainActor
    private func sendManualBatch(_ controller: DiagnosticCollectionController, now: Date) async {
        controller.setForeground(true)
        await controller.sendNow(now: now)
        controller.setForeground(false)
    }

    private func capturedEvent(error: any Error) throws -> BackendDiagnostics.Event {
        let recorder = FailureEventRecorder()
        let diagnostics = BackendDiagnostics(enabled: true, sink: recorder.append)
        diagnostics.recordFailure(.rpc, error: error)
        return try XCTUnwrap(recorder.events.first)
    }

    private func assertPrivateValuesAbsent(_ event: BackendDiagnostics.Event) throws {
        let json = try serialized(event)
        for token in ["private-account", "private-token", "private-response", "private-blessing", "private.invalid"] {
            XCTAssertFalse(json.contains(token), "Private value must not enter diagnostics: \(token)")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(event)) as? [String: Any])
        let allowed: Set<String> = ["kind", "startedAt", "durationMilliseconds", "stage", "requestKind", "outcome",
            "httpStatus", "transportErrorCode", "payloadBytes", "receivedBytes", "errorSource", "errorCode", "errorCategory"]
        XCTAssertTrue(Set(object.keys).isSubset(of: allowed))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func serialized(_ event: BackendDiagnostics.Event) throws -> String {
        String(decoding: try encoded(event), as: UTF8.self)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticFailures-\(UUID())", isDirectory: true)
    }

    private func event(_ now: Date, duration: Double, outcome: BackendOutcome = .success) -> BackendDiagnostics.Event {
        .init(kind: .request, startedAt: now, durationMilliseconds: duration, stage: nil, requestKind: .rpc,
            outcome: outcome, httpStatus: nil, transportErrorCode: nil, payloadBytes: nil, receivedBytes: nil)
    }
}

private final class FailureEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [BackendDiagnostics.Event] = []
    var events: [BackendDiagnostics.Event] { lock.withLock { captured } }
    func append(_ event: BackendDiagnostics.Event) { lock.withLock { captured.append(event) } }
}

private actor FailureDiagnosticUploader: BackendDiagnosticUploading {
    private var failures: Int
    private let error: any Error
    private(set) var reports: [BackendDiagnosticReport] = []
    init(failures: Int, error: any Error) { self.failures = failures; self.error = error }
    func upload(_ report: BackendDiagnosticReport, accountID: UUID) async throws {
        reports.append(report)
        if failures > 0 { failures -= 1; throw error }
    }
    func waitForCount(_ count: Int) async -> Bool {
        for _ in 0..<150 {
            if reports.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
