import XCTest
import Network
import Supabase
@testable import BlessingCircle

final class BackendDiagnosticsTests: XCTestCase {
    func testDisabledDiagnosticsEmitNeitherSpansNorExplicitEvents() {
        let captured = DiagnosticsEvents()
        let diagnostics = BackendDiagnostics(enabled: false, sink: captured.append)
        diagnostics.begin(.submit).finish(.failure)
        diagnostics.record(.init(kind: .request, startedAt: .now, durationMilliseconds: 1,
            stage: nil, requestKind: .blessings, outcome: .success, httpStatus: 200,
            transportErrorCode: nil, payloadBytes: 1, receivedBytes: 2))
        diagnostics.beginRequest(.blessings).finish(httpStatus: 200)
        XCTAssertTrue(captured.events.isEmpty)
    }

    func testTypedSpanSerializesOnlyItsMeasurementFields() throws {
        let captured = DiagnosticsEvents()
        let diagnostics = BackendDiagnostics(enabled: true, sink: captured.append)
        let before = Date()
        diagnostics.begin(.submissionPrepare).finish(.success)
        let after = Date()
        let event = try XCTUnwrap(captured.events.first)
        XCTAssertEqual(captured.events.count, 1)
        XCTAssertEqual(event.kind, .stage)
        XCTAssertEqual(event.stage, .submissionPrepare)
        XCTAssertEqual(event.outcome, .success)
        XCTAssertGreaterThanOrEqual(event.startedAt, before)
        XCTAssertLessThanOrEqual(event.startedAt, after)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(event.durationMilliseconds), 0)
        let json = try jsonObject(event)
        XCTAssertEqual(Set(json.keys), ["kind", "startedAt", "durationMilliseconds", "stage", "outcome"])
        XCTAssertEqual(json["stage"] as? String, "submissionPrepare")
        XCTAssertEqual(json["outcome"] as? String, "success")
    }

    func testSuccessfulRequestEmitsSanitizedMetrics() async throws {
        let event = try await requestEvent(scenario: "success")
        XCTAssertEqual(event.kind, .request)
        XCTAssertEqual(event.requestKind, .blessings)
        XCTAssertEqual(event.outcome, .success)
        XCTAssertEqual(event.httpStatus, 200)
        XCTAssertNil(event.transportErrorCode)
        XCTAssertNil(event.errorSource)
        XCTAssertNil(event.errorCode)
        XCTAssertNil(event.errorCategory)
        try assertPrivateValuesAbsent(event)
    }

    func testForbiddenRequestRecordsFailureWithoutResponseContent() async throws {
        let event = try await requestEvent(scenario: "forbidden")
        XCTAssertEqual(event.requestKind, .blessings)
        XCTAssertEqual(event.outcome, .failure)
        XCTAssertNil(event.httpStatus, "The SDK error does not expose the HTTP response status")
        XCTAssertNil(event.transportErrorCode)
        XCTAssertEqual(event.errorSource, .postgrest)
        XCTAssertEqual(event.errorCode, "42501")
        XCTAssertEqual(event.errorCategory, .other)
        try assertPrivateValuesAbsent(event)
    }

    func testTransportFailureRecordsNumericURLCodeAndSanitizedClassification() async throws {
        let event = try await requestEvent(scenario: "transport")
        XCTAssertEqual(event.outcome, .failure)
        XCTAssertNotNil(event.transportErrorCode)
        XCTAssertEqual(event.errorSource, .url)
        XCTAssertEqual(event.errorCode, event.transportErrorCode.map { String($0) })
        XCTAssertEqual(event.errorCategory, .other)
        XCTAssertNil(event.httpStatus)
        try assertPrivateValuesAbsent(event)
    }

    func testCancellationIsDistinctFromFailure() async throws {
        let event = try await requestEvent(scenario: "cancelled")
        XCTAssertEqual(event.outcome, .cancelled)
        // Structured cancellation may become CancellationError inside the SDK,
        // which has no URL transport code to report.
        XCTAssertTrue(event.transportErrorCode == nil || event.transportErrorCode == NSURLErrorCancelled)
        XCTAssertNil(event.errorSource)
        XCTAssertNil(event.errorCode)
        XCTAssertNil(event.errorCategory)
        try assertPrivateValuesAbsent(event)
    }

    func testRequestSpanPreservesOnlyNumericURLTransportError() throws {
        let captured = DiagnosticsEvents()
        let diagnostics = BackendDiagnostics(enabled: true, sink: captured.append)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled,
            userInfo: [NSLocalizedDescriptionKey: "private-token private-error-body",
                NSURLErrorFailingURLErrorKey: URL(string: "https://private-account.invalid/private-person")!])
        diagnostics.beginRequest(.storageUpload, payloadBytes: 20).finish(error: error)
        let event = try XCTUnwrap(captured.events.first)
        XCTAssertEqual(event.outcome, .cancelled)
        XCTAssertEqual(event.transportErrorCode, NSURLErrorCancelled)
        XCTAssertNil(event.errorSource)
        XCTAssertNil(event.errorCode)
        XCTAssertNil(event.errorCategory)
        try assertPrivateValuesAbsent(event)
    }

    func testDataUploadEmitsSanitizedMetrics() async throws {
        let event = try await requestEvent(scenario: "success", upload: .data)
        XCTAssertEqual(event.requestKind, .storageUpload)
        XCTAssertEqual(event.outcome, .success)
        XCTAssertNil(event.httpStatus, "The SDK upload result does not expose the HTTP response status")
        XCTAssertEqual(event.payloadBytes, Int64(Data("private-blessing-body".utf8).count))
        try assertPrivateValuesAbsent(event)
    }

    func testFileUploadEmitsSanitizedMetrics() async throws {
        let event = try await requestEvent(scenario: "success", upload: .file)
        XCTAssertEqual(event.requestKind, .storageUpload)
        XCTAssertEqual(event.outcome, .success)
        XCTAssertNil(event.httpStatus, "The SDK upload result does not expose the HTTP response status")
        XCTAssertEqual(event.payloadBytes, Int64(Data("private-blessing-body".utf8).count))
        try assertPrivateValuesAbsent(event)
    }

    func testSignedURLReturnsPrivateURLWithoutLoggingIt() async throws {
        let event = try await requestEvent(scenario: "success", upload: .signing)
        XCTAssertEqual(event.requestKind, .storageSign)
        XCTAssertEqual(event.outcome, .success)
        XCTAssertNil(event.httpStatus)
        XCTAssertNil(event.payloadBytes)
        try assertPrivateValuesAbsent(event)
    }

    func testDisabledMeasuredSDKRequestStillReturnsDecodedResponse() async throws {
        let server = try DiagnosticsHTTPServer(scenario: "success", received: {})
        let port = try await server.start()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let captured = DiagnosticsEvents()
        let diagnostics = BackendDiagnostics(enabled: false, sink: captured.append)
        let response: PostgrestResponse<DiagnosticsFixtureBody> = try await makeClient(port: port, session: session)
            .from("blessings").select().measuredExecute(.blessings, diagnostics: diagnostics)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.value.body, "private-blessing-body")
        XCTAssertTrue(captured.events.isEmpty)
    }

    func testVoidMeasuredSDKRequestRecordsOneLogicalOperation() async throws {
        let server = try DiagnosticsHTTPServer(scenario: "success", received: {})
        let port = try await server.start()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let captured = DiagnosticsEvents()
        let diagnostics = BackendDiagnostics(enabled: true, sink: captured.append)
        let response: PostgrestResponse<Void> = try await makeClient(port: port, session: session)
            .from("blessings").select().measuredExecute(.blessings, diagnostics: diagnostics)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(captured.events.count, 1)
        let event = try XCTUnwrap(captured.events.first)
        XCTAssertEqual(event.requestKind, .blessings)
        XCTAssertEqual(event.receivedBytes, Int64(response.data.count))
        try assertPrivateValuesAbsent(event)
    }

    private enum Upload { case data, file, signing }

    private func requestEvent(scenario: String, upload: Upload? = nil) async throws -> BackendDiagnostics.Event {
        let completed = expectation(description: "Request diagnostic delivered")
        let captured = DiagnosticsEvents()
        let diagnostics = BackendDiagnostics(enabled: true) { event in
            captured.append(event)
            completed.fulfill()
        }
        let received = scenario == "cancelled" ? expectation(description: "Loopback server received request") : nil
        let server = try DiagnosticsHTTPServer(scenario: scenario) { received?.fulfill() }
        let port = try await server.start()
        defer { server.stop() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = makeClient(port: port, session: session)
        let body = Data("private-blessing-body".utf8)
        let uploadFile = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID()).mov")
        if upload == .file { try body.write(to: uploadFile) }
        defer { try? FileManager.default.removeItem(at: uploadFile) }
        let work = Task {
            switch upload {
            case .data:
                _ = try await client.storage.from("private-bucket").measuredUpload("private-person.mov",
                    data: body, options: .init(contentType: "video/quicktime"), diagnostics: diagnostics)
            case .file:
                _ = try await client.storage.from("private-bucket").measuredUpload("private-person.mov",
                    fileURL: uploadFile, options: .init(contentType: "video/quicktime"), diagnostics: diagnostics)
            case .signing:
                let signed = try await client.storage.from("private-bucket").measuredSignedURL(
                    path: "private-person.mov", expiresIn: 60, diagnostics: diagnostics)
                XCTAssertTrue(signed.absoluteString.contains("private-token"))
            case nil:
                let response: PostgrestResponse<DiagnosticsFixtureBody> = try await client.from("blessings")
                    .select().eq("user_id", value: "private-person")
                    .measuredExecute(.blessings, diagnostics: diagnostics)
                XCTAssertEqual(response.value.body, "private-blessing-body")
                XCTAssertEqual(response.value.token, "private-token")
            }
        }
        if let received {
            await fulfillment(of: [received], timeout: 3)
            work.cancel()
        }
        do {
            _ = try await work.value
            XCTAssertEqual(scenario, "success")
        } catch {
            XCTAssertTrue(["transport", "cancelled", "forbidden"].contains(scenario), "Unexpected request failure")
        }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(captured.events.count, 1)
        return try XCTUnwrap(captured.events.first)
    }

    private func jsonObject(_ event: BackendDiagnostics.Event) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
    }

    private func makeClient(port: UInt16, session: URLSession) -> SupabaseClient {
        SupabaseClient(supabaseURL: URL(string: "http://127.0.0.1:\(port)")!, supabaseKey: "synthetic-key",
            options: .init(auth: .init(storage: DiagnosticsAuthStorage(), autoRefreshToken: false,
                accessToken: { "private-token" }), global: .init(session: session)))
    }

    private func assertPrivateValuesAbsent(_ event: BackendDiagnostics.Event,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let json = try jsonObject(event)
        let allowedKeys: Set<String> = ["kind", "startedAt", "durationMilliseconds", "requestKind",
            "outcome", "httpStatus", "transportErrorCode", "payloadBytes", "receivedBytes",
            "errorSource", "errorCode", "errorCategory"]
        XCTAssertTrue(Set(json.keys).isSubset(of: allowedKeys), file: file, line: line)
        if let code = event.errorCode {
            XCTAssertNotNil(code.range(of: "^[A-Za-z0-9_-]{1,16}$", options: .regularExpression),
                "Only a bounded structured error code may enter the payload", file: file, line: line)
        }
        if event.errorSource != nil || event.errorCode != nil || event.errorCategory != nil {
            XCTAssertEqual(event.outcome, .failure, file: file, line: line)
            XCTAssertNotNil(event.errorSource, file: file, line: line)
            XCTAssertNotNil(event.errorCategory, file: file, line: line)
        }
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        for forbidden in ["private-", "Authorization", "https://", "http://", "127.0.0.1", "user_id", "scenario", "NSLocalizedDescription"] {
            XCTAssertFalse(encoded.contains(forbidden), forbidden, file: file, line: line)
        }
        XCTAssertNil(event.stage, file: file, line: line)
        // Duration must be finite even if the transport supplies no transaction timing.
        if let duration = event.durationMilliseconds {
            XCTAssertGreaterThanOrEqual(duration, 0, file: file, line: line)
        }
    }
}

private final class DiagnosticsEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [BackendDiagnostics.Event] = []
    var events: [BackendDiagnostics.Event] { lock.withLock { captured } }
    func append(_ event: BackendDiagnostics.Event) { lock.withLock { captured.append(event) } }
}

private struct DiagnosticsFixtureBody: Decodable {
    let body: String
    let token: String
}

private struct DiagnosticsAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

/// A per-test HTTP listener binds only to loopback. No hosted service is contacted.
/// Real URLSession transfers exercise delegate delivery, async uploads, and cancellation.
private final class DiagnosticsHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "BackendDiagnostics.loopback")
    private let scenario: String
    private let received: @Sendable () -> Void
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    init(scenario: String, received: @escaping @Sendable () -> Void) throws {
        self.scenario = scenario
        self.received = received
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.withLock { self.connections.append(connection) }
            connection.start(queue: self.queue)
            self.read(connection, buffered: Data())
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    guard let port = self.listener.port else {
                        continuation.resume(throwing: URLError(.cannotConnectToHost))
                        return
                    }
                    continuation.resume(returning: port.rawValue)
                case let .failed(error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        let outstanding = lock.withLock { let result = connections; connections = []; return result }
        outstanding.forEach { $0.cancel() }
    }

    private func read(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, ended, error in
            guard let self else { connection.cancel(); return }
            var accumulated = buffered
            if let data { accumulated.append(data) }
            guard let boundary = accumulated.range(of: Data("\r\n\r\n".utf8)) else {
                if ended || error != nil { connection.cancel() }
                else { self.read(connection, buffered: accumulated) }
                return
            }
            let headers = String(decoding: accumulated[..<boundary.lowerBound], as: UTF8.self)
            let contentLength = headers.split(separator: "\n").first {
                $0.lowercased().hasPrefix("content-length:")
            }.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
            guard accumulated.count - boundary.upperBound >= contentLength else {
                if ended || error != nil { connection.cancel() }
                else { self.read(connection, buffered: accumulated) }
                return
            }
            self.received()
            if self.scenario == "cancelled" { return } // Remain pending until the caller cancels.
            if self.scenario == "transport" { connection.cancel(); return }
            let body: String
            if self.scenario == "forbidden" {
                body = #"{"code":"42501","message":"private-error-body private-token","details":"private-person","hint":"private-hint"}"#
            } else if headers.contains("/storage/v1/object/sign/") {
                body = #"{"signedURL":"/object/sign/private-bucket/private-person.mov?token=private-token"}"#
            } else if headers.contains("/storage/v1/object/") {
                body = #"{"Id":"private-person","Key":"private-bucket/private-person.mov"}"#
            } else {
                body = #"{"body":"private-blessing-body","token":"private-token"}"#
            }
            let status = self.scenario == "forbidden" ? "403 Forbidden" : "200 OK"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nprivate-response-header: private-person\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
