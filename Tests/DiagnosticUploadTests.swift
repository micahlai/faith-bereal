import Foundation
import Supabase
import XCTest
@testable import BlessingCircle

/// Exercises the actual PostgREST uploader with cached synthetic auth and a
/// transport that intercepts every request; no hosted backend is contacted.
final class DiagnosticUploadTests: XCTestCase {
    func testUploaderPinsAccountTokenAndMatchesIngestContractWithoutCollectingItself() async throws {
        let fixture = try DiagnosticUploadFixture()
        defer { fixture.close() }
        let report = makeReport()
        fixture.acceptedCount = report.events.count
        let recorder = DiagnosticUploadRecorder()
        BackendDiagnostics.shared.setCollectionSink(recorder.append)
        defer { BackendDiagnostics.shared.setCollectionSink(nil) }

        try await fixture.uploader.upload(report, accountID: fixture.accountID)

        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/ingest_backend_diagnostics")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-diagnostic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "synthetic-diagnostic-key")
        let params = try XCTUnwrap(fixture.payloads.first)
        XCTAssertEqual(Set(params.keys), ["p_report_id", "p_session_id", "p_build_number", "p_events"])
        XCTAssertEqual((params["p_report_id"] as? String).flatMap(UUID.init(uuidString:)), report.reportID)
        XCTAssertEqual((params["p_session_id"] as? String).flatMap(UUID.init(uuidString:)), report.sessionID)
        XCTAssertEqual(params["p_build_number"] as? Int, 31)
        let events = try XCTUnwrap(params["p_events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 2)
        let timestamp = ISO8601DateFormatter()
        for event in events {
            let value = try XCTUnwrap(event["startedAt"] as? String)
            XCTAssertTrue(value.hasSuffix("Z"))
            XCTAssertNotNil(timestamp.date(from: value))
            XCTAssertEqual(event["outcome"] as? String, "success")
            XCTAssertEqual(event["durationMilliseconds"] as? Double, 20)
        }
        XCTAssertEqual(Set(events[0].keys), ["kind", "startedAt", "durationMilliseconds", "stage", "outcome"])
        XCTAssertEqual(events[0]["kind"] as? String, "stage")
        XCTAssertEqual(events[0]["stage"] as? String, "bootstrapVisible")
        XCTAssertEqual(Set(events[1].keys), ["kind", "startedAt", "durationMilliseconds", "requestKind", "outcome", "httpStatus", "payloadBytes", "receivedBytes"])
        XCTAssertEqual(events[1]["kind"] as? String, "request")
        XCTAssertEqual(events[1]["requestKind"] as? String, "blessings")
        XCTAssertEqual(events[1]["httpStatus"] as? Int, 200)
        XCTAssertEqual(recorder.count, 0, "Uploading metrics must never create another metric")
    }

    func testUploaderRejectsPartialAcknowledgement() async throws {
        let fixture = try DiagnosticUploadFixture()
        defer { fixture.close() }
        fixture.acceptedCount = 1
        do {
            try await fixture.uploader.upload(makeReport(), accountID: fixture.accountID)
            XCTFail("A partial acknowledgement must leave the report available to retry")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badServerResponse)
        }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testUploaderRejectsAccountMismatchBeforeAnyHTTPRequest() async throws {
        let fixture = try DiagnosticUploadFixture()
        defer { fixture.close() }
        do {
            try await fixture.uploader.upload(makeReport(), accountID: UUID())
            XCTFail("A different cached account cannot upload the captured account's report")
        } catch is CancellationError { }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testUploaderRejectsMalformedAcknowledgement() async throws {
        let fixture = try DiagnosticUploadFixture()
        defer { fixture.close() }
        fixture.responseOverride = Data(#"{"accepted":2}"#.utf8)
        do {
            try await fixture.uploader.upload(makeReport(), accountID: fixture.accountID)
            XCTFail("Only the server's exact integer count can acknowledge a report")
        } catch is DecodingError { }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testFailedConsentWriteCannotEnableCollectionInMemory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticConsentFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        // A regular file at the queue's directory path deterministically makes
        // persistence fail, without relying on sandbox or file permissions.
        try Data("blocked directory".utf8).write(to: root)
        let store = BackendDiagnosticStore(root: root)
        let account = UUID()
        let initial = try await store.load(accountID: account)
        XCTAssertFalse(initial.isEnabled)
        do {
            _ = try await store.setConsent(accountID: account, enabled: true)
            XCTFail("Consent must report the failed disk write")
        } catch { }
        let afterFailure = try await store.load(accountID: account)
        XCTAssertFalse(afterFailure.isEnabled, "A failed save must not become consent during summary refresh")
        XCTAssertNil(afterFailure.sessionID)
    }

    @MainActor
    func testFailedOptOutStaysPausedThroughSummaryRefreshAndCanBeRetried() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticOptOutFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BackendDiagnosticStore(root: root)
        let diagnostics = BackendDiagnostics(enabled: false)
        let controller = DiagnosticCollectionController(store: store, diagnostics: diagnostics, buildNumber: 31)
        defer { controller.deactivate() }
        await controller.activate(accountID: UUID())
        await controller.setEnabled(true)
        XCTAssertTrue(diagnostics.enabled)
        try FileManager.default.removeItem(at: root)
        try Data("blocked directory".utf8).write(to: root)

        await controller.setEnabled(false)
        await controller.refreshSummary()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(diagnostics.enabled)
        XCTAssertTrue(controller.status?.contains("paused") == true)

        try FileManager.default.removeItem(at: root)
        await controller.setEnabled(false)
        await controller.refreshSummary()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(diagnostics.enabled)
        XCTAssertNil(controller.status)
    }

    @MainActor
    func testFailedSignOutRestoresSameAccountsCollectionAndConsentControls() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticSignOutFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let accountID = bootstrap.currentUser.id
        let store = BackendDiagnosticStore(root: root)
        let diagnostics = BackendDiagnostics(enabled: false)
        let collection = DiagnosticCollectionController(store: store, diagnostics: diagnostics, buildNumber: 31)
        defer { collection.deactivate() }
        let model = AppModel(repository: repository,
            authentication: FailingDiagnosticSignOutAuthentication(accountID: accountID),
            diagnosticCollection: collection)
        model.currentUser = bootstrap.currentUser
        await collection.activate(accountID: accountID)
        await collection.setEnabled(true)
        let before = try await store.load(accountID: accountID)

        await model.signOut()

        XCTAssertEqual(model.currentUser?.id, accountID)
        XCTAssertTrue(collection.isEnabled)
        XCTAssertTrue(diagnostics.enabled)
        let restored = try await store.load(accountID: accountID)
        XCTAssertNotEqual(restored.sessionID, before.sessionID)
        try await store.append(accountID: accountID, sessionID: XCTUnwrap(restored.sessionID),
            buildNumber: 31, event: makeReport().events[0])
        await collection.refreshSummary()
        XCTAssertEqual(collection.queuedCount, 1)
        await collection.setEnabled(false)
        XCTAssertFalse(collection.isEnabled, "Failed sign-out must not leave the consent switch disconnected")
        XCTAssertFalse(diagnostics.enabled)
    }

    private func makeReport() -> BackendDiagnosticReport {
        let now = Date()
        return BackendDiagnosticReport(reportID: UUID(), sessionID: UUID(), buildNumber: 31, events: [
            .init(kind: .stage, startedAt: now, durationMilliseconds: 20, stage: .bootstrapVisible,
                requestKind: nil, outcome: .success, httpStatus: nil, transportErrorCode: nil,
                payloadBytes: nil, receivedBytes: nil),
            .init(kind: .request, startedAt: now, durationMilliseconds: 20, stage: nil,
                requestKind: .blessings, outcome: .success, httpStatus: 200, transportErrorCode: nil,
                payloadBytes: 100, receivedBytes: 200)
        ])
    }
}

private actor FailingDiagnosticSignOutAuthentication: AuthenticationProviding {
    let accountID: UUID
    init(accountID: UUID) { self.accountID = accountID }
    func hasSession() async -> Bool { true }
    func currentUserID() async -> UUID? { accountID }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws { }
    func signOut() async throws { throw URLError(.notConnectedToInternet) }
}

private final class DiagnosticUploadFixture: @unchecked Sendable {
    let accountID = UUID()
    let host = "diagnostic-upload-\(UUID().uuidString.lowercased()).invalid"
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []
    private var capturedPayloads: [[String: Any]] = []
    private var count = 2
    private var overriddenResponse: Data?
    private var session: URLSession!
    private(set) var uploader: SupabaseDiagnosticUploader!

    var requests: [URLRequest] { lock.withLock { capturedRequests } }
    var payloads: [[String: Any]] { lock.withLock { capturedPayloads } }
    var acceptedCount: Int {
        get { lock.withLock { count } }
        set { lock.withLock { count = newValue } }
    }
    var responseOverride: Data? {
        get { lock.withLock { overriddenResponse } }
        set { lock.withLock { overriddenResponse = newValue } }
    }

    init() throws {
        let now = Date(), storage = DiagnosticUploadAuthStorage()
        let user = User(id: accountID, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now)
        let auth = Session(accessToken: "synthetic-diagnostic-token", tokenType: "bearer", expiresIn: 3600,
            expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970,
            refreshToken: "synthetic-diagnostic-refresh", user: user)
        try storage.store(key: "diagnostic-test-session", value: JSONEncoder().encode(auth))
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [DiagnosticUploadURLProtocol.self]
        session = URLSession(configuration: transport)
        DiagnosticUploadURLProtocol.register(self)
        let url = URL(string: "https://\(host)")!
        let client = SupabaseClient(supabaseURL: url, supabaseKey: "synthetic-diagnostic-key",
            options: .init(auth: .init(storage: storage, storageKey: "diagnostic-test-session", autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true), global: .init(session: session)))
        uploader = SupabaseDiagnosticUploader(client: client,
            configuration: BackendConfiguration(supabaseURL: url, publishableKey: "synthetic-diagnostic-key"), session: session)
    }

    func close() {
        session.invalidateAndCancel()
        DiagnosticUploadURLProtocol.unregister(host: host)
    }

    func response(for request: URLRequest) throws -> Data {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var body = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&bytes, maxLength: bytes.count)
                guard read >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if read == 0 { break }
                body.append(contentsOf: bytes.prefix(read))
            }
            data = body
        }
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        return lock.withLock {
            capturedRequests.append(request)
            capturedPayloads.append(payload)
            return overriddenResponse ?? Data("\(count)".utf8)
        }
    }
}

private final class DiagnosticUploadAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private final class DiagnosticUploadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [BackendDiagnostics.Event] = []
    var count: Int { lock.withLock { events.count } }
    func append(_ event: BackendDiagnostics.Event) { lock.withLock { events.append(event) } }
}

private final class DiagnosticUploadURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: DiagnosticUploadFixture] = [:]
    }
    private static let registry = Registry()
    static func register(_ fixture: DiagnosticUploadFixture) {
        registry.lock.withLock { registry.fixtures[fixture.host] = fixture }
    }
    static func unregister(host: String) { _ = registry.lock.withLock { registry.fixtures.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url,
                  let fixture = Self.registry.lock.withLock({ Self.registry.fixtures[url.host ?? ""] }) else {
                throw URLError(.unsupportedURL)
            }
            let data = try fixture.response(for: request)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
