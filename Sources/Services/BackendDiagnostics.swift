import Foundation
import OSLog
import Supabase

enum BackendErrorSource: String, Codable, Sendable { case postgrest, storage, auth, url, speech, audio, other }
enum BackendErrorCategory: String, Codable, Sendable { case connectionLimit, other }

/// Only closed sources/categories and structured codes cross the collection boundary.
/// Messages are inspected locally for classification, never retained in the payload.
struct BackendDiagnosticFailure: Sendable {
    let source: BackendErrorSource
    let code: String?
    let category: BackendErrorCategory

    static func capture(error: any Error) -> Self {
        var source = BackendErrorSource.other
        var code: String?
        if let error = error as? PostgrestError {
            source = .postgrest
            if let raw = error.code,
               raw.range(of: "^(?:[A-Z0-9]{5}|PGRST[0-9]{3})$", options: .regularExpression) != nil { code = raw }
        } else if let error = error as? StorageError {
            source = .storage
            if let raw = error.statusCode, let status = Int(raw), (100...599).contains(status) { code = String(status) }
        } else if let error = error as? AuthError {
            source = .auth
            // Auth codes are an open string vocabulary; retain only known short
            // constants, otherwise the typed HTTP status is useful and bounded.
            let known = ["unknown", "bad_json", "bad_jwt", "not_admin", "user_not_found",
                         "session_expired", "request_timeout", "conflict", "hook_timeout"]
            if known.contains(error.errorCode.rawValue) { code = error.errorCode.rawValue }
            else if case let .api(_, _, _, response) = error { code = String(response.statusCode) }
        } else {
            let ns = error as NSError
            switch ns.domain {
            case NSURLErrorDomain: source = .url
            case "kAFAssistantErrorDomain", "kLSRErrorDomain", "SFSpeechErrorDomain": source = .speech
            case "AVFAudioErrorDomain", "AVFoundationErrorDomain", NSOSStatusErrorDomain: source = .audio
            default: break
            }
            if source != .other, String(ns.code).count <= 16 { code = String(ns.code) }
        }
        let message = error.localizedDescription.lowercased()
        let connectionLimit = code == "53300" || code == "PGRST003"
            || message.contains("too many connections") || message.contains("remaining connection slots")
            || message.contains("max client connections") || message.contains("maxclientsinsessionmode")
        return Self(source: source, code: code, category: connectionLimit ? .connectionLimit : .other)
    }
}

/// Closed vocabulary: never emit URLs, filters, headers, bodies, IDs, or error descriptions.
enum BackendRequestKind: String, Codable, Sendable {
    case auth, circles, members, profiles, prompts, blessings, responses
    case rpc, storageSign, storageUpload, storageOther, function, other
    case speech, audio, diagnosticsUpload


}

enum BackendStage: String, Codable, Sendable {
    case bootstrapVisible, circleSwitch, circleRefresh, timelineRefresh, submit
    case submissionPrepare, thumbnail, uploadAudio, uploadPhoto, uploadVideo, uploadThumbnail
    case finalize, mediaSigning, widgetRefresh, automaticSaving
}

enum BackendOutcome: String, Codable, Sendable { case success, failure, cancelled }

/// Opt-in local diagnostics. No network exporter or persistent in-memory request history.
final class BackendDiagnostics: @unchecked Sendable {
    struct Event: Codable, Sendable {
        enum Kind: String, Codable, Sendable { case stage, request }
        let kind: Kind
        let startedAt: Date
        let durationMilliseconds: Double?
        let stage: BackendStage?
        let requestKind: BackendRequestKind?
        let outcome: BackendOutcome
        let httpStatus: Int?
        let transportErrorCode: Int?
        let payloadBytes: Int64?
        let receivedBytes: Int64?
        var errorSource: BackendErrorSource? = nil
        var errorCode: String? = nil
        var errorCategory: BackendErrorCategory? = nil
    }

    static let shared = BackendDiagnostics(
        enabled: ProcessInfo.processInfo.environment["MANNA_BACKEND_DIAGNOSTICS"] == "1"
    )
    private static let logger = Logger(subsystem: "app.manna-circle.ios", category: "BackendPerformance")
    private let localEnabled: Bool
    private let lock = NSLock()
    private var collectionSink: (@Sendable (Event) -> Void)?
    var enabled: Bool { localEnabled || lock.withLock { collectionSink != nil } }
    private let sink: @Sendable (Event) -> Void

    init(enabled: Bool, sink: @escaping @Sendable (Event) -> Void = BackendDiagnostics.log) {
        self.localEnabled = enabled
        self.sink = sink
    }

    func record(_ event: Event) {
        record(event, collection: lock.withLock { collectionSink })
    }

    private func record(_ event: Event, collection: (@Sendable (Event) -> Void)?) {
        if localEnabled { sink(event) }
        collection?(event)
    }

    func setCollectionSink(_ collection: (@Sendable (Event) -> Void)?) {
        lock.withLock { collectionSink = collection }
    }

    func begin(_ stage: BackendStage) -> Span {
        Span(diagnostics: self, stage: stage, collection: lock.withLock { collectionSink })
    }

    // Counts SDK operations, not physical HTTP attempts. Retry time is included.
    func beginRequest(_ kind: BackendRequestKind, payloadBytes: Int64? = nil) -> RequestSpan {
        RequestSpan(diagnostics: self, kind: kind, payloadBytes: payloadBytes, collection: lock.withLock { collectionSink })
    }

    func recordFailure(_ kind: BackendRequestKind, error: any Error) {
        let ns = error as NSError
        guard !(error is CancellationError), !(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) else { return }
        recordFailure(kind, failure: .capture(error: error))
    }

    func recordFailure(_ kind: BackendRequestKind, failure: BackendDiagnosticFailure) {
        record(Event(kind: .request, startedAt: .now, durationMilliseconds: 0, stage: nil,
            requestKind: kind, outcome: .failure, httpStatus: nil, transportErrorCode: nil,
            payloadBytes: nil, receivedBytes: nil, errorSource: failure.source,
            errorCode: failure.code, errorCategory: failure.category))
    }

    struct RequestSpan: Sendable {
        let diagnostics: BackendDiagnostics
        let kind: BackendRequestKind
        let payloadBytes: Int64?
        let collection: (@Sendable (Event) -> Void)?
        let startedAt = Date()
        let start = ContinuousClock.now

        func finish(httpStatus: Int? = nil, receivedBytes: Int64? = nil, error: (any Error)? = nil) {
            let elapsed = start.duration(to: .now).components
            let code = (error as NSError?).flatMap { $0.domain == NSURLErrorDomain ? $0.code : nil }
            let cancelled = error is CancellationError || code == NSURLErrorCancelled
            let failure = cancelled ? nil : error.map { BackendDiagnosticFailure.capture(error: $0) }
            diagnostics.record(Event(kind: .request, startedAt: startedAt,
                durationMilliseconds: Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15,
                stage: nil, requestKind: kind,
                outcome: cancelled ? .cancelled : (error != nil || (httpStatus ?? 200) >= 400 ? .failure : .success),
                httpStatus: httpStatus, transportErrorCode: code, payloadBytes: payloadBytes,
                receivedBytes: receivedBytes, errorSource: failure?.source,
                errorCode: failure?.code, errorCategory: failure?.category), collection: collection)
        }
    }

    static func log(_ event: Event) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) else { return }
        // Every string comes from a closed enum. No raw network values enter this payload.
        logger.info("backend_metric \(line, privacy: .public)")
    }

    struct Span: Sendable {
        private let diagnostics: BackendDiagnostics
        private let stage: BackendStage
        private let collection: (@Sendable (Event) -> Void)?
        private let startedAt: Date
        private let start: ContinuousClock.Instant

        fileprivate init(diagnostics: BackendDiagnostics, stage: BackendStage, collection: (@Sendable (Event) -> Void)?) {
            self.diagnostics = diagnostics
            self.stage = stage
            self.collection = collection
            startedAt = .now
            start = ContinuousClock.now
        }

        func finish(_ outcome: BackendOutcome) {
            let elapsed = start.duration(to: .now).components
            diagnostics.record(Event(kind: .stage, startedAt: startedAt,
                durationMilliseconds: Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15,
                stage: stage, requestKind: nil, outcome: outcome, httpStatus: nil,
                transportErrorCode: nil, payloadBytes: nil, receivedBytes: nil), collection: collection)
        }
    }
}
