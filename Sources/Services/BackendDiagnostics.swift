import Foundation
import OSLog

/// Closed vocabulary: never emit URLs, filters, headers, bodies, IDs, or error descriptions.
enum BackendRequestKind: String, Codable, Sendable {
    case auth, circles, members, profiles, prompts, blessings, responses
    case rpc, storageSign, storageUpload, storageOther, function, other


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
            diagnostics.record(Event(kind: .request, startedAt: startedAt,
                durationMilliseconds: Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15,
                stage: nil, requestKind: kind,
                outcome: cancelled ? .cancelled : (error != nil || (httpStatus ?? 200) >= 400 ? .failure : .success),
                httpStatus: httpStatus, transportErrorCode: code, payloadBytes: payloadBytes,
                receivedBytes: receivedBytes), collection: collection)
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
