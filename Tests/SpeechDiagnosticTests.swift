import XCTest
@testable import BlessingCircle

final class SpeechDiagnosticTests: XCTestCase {
    @MainActor
    func testRecognitionCallbackPreservesUnderlyingErrorForDiagnosticsAndKeepsMessageLocal() async throws {
        let privateMessage = "Too many connections: private-transcript private-account"
        let error = NSError(domain: "kAFAssistantErrorDomain", code: 1101, userInfo: [
            NSLocalizedDescriptionKey: privateMessage,
            NSFilePathErrorKey: "/private/audio/private-person.caf"
        ])
        let received = await withCheckedContinuation { continuation in
            let handler = SpeechCallbackFactory.makeRecognitionHandler { transcript, isFinal, failure in
                continuation.resume(returning: (transcript, isFinal, failure))
            }
            handler(nil, error)
        }
        XCTAssertNil(received.0)
        XCTAssertFalse(received.1)
        let failure = try XCTUnwrap(received.2)
        XCTAssertEqual(failure.message, privateMessage, "The existing local error message is preserved")

        let captured = SpeechDiagnosticEvents()
        let diagnostics = BackendDiagnostics(enabled: true, sink: captured.append)
        diagnostics.recordFailure(.speech, failure: failure.diagnostic)
        let event = try XCTUnwrap(captured.events.first)
        XCTAssertEqual(captured.events.count, 1)
        XCTAssertEqual(event.requestKind, .speech)
        XCTAssertEqual(event.outcome, .failure)
        XCTAssertEqual(event.errorSource, .speech)
        XCTAssertEqual(event.errorCode, "1101")
        XCTAssertEqual(event.errorCategory, .connectionLimit)
        let serialized = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        XCTAssertTrue(serialized.contains("1101"), "The underlying numeric Speech error code survives the actor hop")
        for privateValue in [privateMessage, "private-transcript", "private-account", "private-person", "/private/audio"] {
            XCTAssertFalse(serialized.contains(privateValue))
        }
    }

    @MainActor
    func testRecognitionCallbackWithoutErrorDoesNotInventFailure() async {
        let received = await withCheckedContinuation { continuation in
            let handler = SpeechCallbackFactory.makeRecognitionHandler { transcript, isFinal, failure in
                continuation.resume(returning: (transcript, isFinal, failure))
            }
            handler(nil, nil)
        }
        XCTAssertNil(received.0)
        XCTAssertFalse(received.1)
        XCTAssertNil(received.2)
    }
}

private final class SpeechDiagnosticEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BackendDiagnostics.Event] = []
    var events: [BackendDiagnostics.Event] { lock.withLock { storage } }
    func append(_ event: BackendDiagnostics.Event) { lock.withLock { storage.append(event) } }
}
