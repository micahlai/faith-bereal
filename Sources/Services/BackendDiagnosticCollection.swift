import Foundation
import Observation
import Supabase

struct BackendDiagnosticReport: Codable, Sendable {
    let reportID: UUID
    let sessionID: UUID
    let buildNumber: Int
    let events: [BackendDiagnostics.Event]
}

struct DiagnosticCollectionSnapshot: Sendable {
    let isEnabled: Bool
    let sessionID: UUID?
    let queuedCount: Int
    let lastUploadedAt: Date?
}

/// Serialized, account-isolated, bounded disk queue. No media/content enters these types.
actor BackendDiagnosticStore {
    static let maximumEvents = 1_000
    static let batchSize = 100
    static let localLifetime: TimeInterval = 13 * 86_400
    private struct Captured: Codable {
        let sessionID: UUID
        let buildNumber: Int
        let event: BackendDiagnostics.Event
    }
    private struct State: Codable {
        var isEnabled = false
        // Optional for build-31 files, whose stored false cannot distinguish a
        // previous opt-out from the original default. Preserve those choices.
        var consentWasChosen: Bool? = false
        var sessionID: UUID?
        var pending: [Captured] = []
        var report: BackendDiagnosticReport?
        var lastUploadedAt: Date?
    }
    private let root: URL
    nonisolated let defaultsToEnabled: Bool
    private var states: [UUID: State] = [:]
    private var checkpointTask: Task<Void, Never>?

    init(root: URL? = nil, defaultEnabled: Bool = false) {
        defaultsToEnabled = defaultEnabled
#if DEBUG
        if root == nil, let session = ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SAVING_TEST_SESSION"],
           let id = UUID(uuidString: session) {
            self.root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticUITests/\(id.uuidString)")
            return
        }
#endif
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackendDiagnostics", isDirectory: true)
    }

    func load(accountID: UUID, now: Date = .now) throws -> DiagnosticCollectionSnapshot {
        if states[accountID] == nil {
            if FileManager.default.fileExists(atPath: file(accountID).path) {
                var state = try Self.decoder().decode(State.self, from: Data(contentsOf: file(accountID)))
                if state.consentWasChosen == false, state.isEnabled != defaultsToEnabled {
                    state.isEnabled = defaultsToEnabled
                    if !defaultsToEnabled { state.pending = []; state.report = nil }
                    try persist(accountID, state: state)
                }
                states[accountID] = state
            } else {
                var state = State()
                state.isEnabled = defaultsToEnabled
                // Default-on must be durable before capture can observe it.
                if defaultsToEnabled { try persist(accountID, state: state) }
                states[accountID] = state
            }
        }
        prune(accountID, now: now)
        return snapshot(accountID)
    }

    func beginSession(accountID: UUID, now: Date = .now) throws -> DiagnosticCollectionSnapshot {
        _ = try load(accountID: accountID, now: now)
        var state = states[accountID] ?? State()
        state.sessionID = UUID()
        try persist(accountID, state: state)
        states[accountID] = state
        return snapshot(accountID)
    }

    func endSession(accountID: UUID, sessionID: UUID) throws {
        guard states[accountID]?.sessionID == sessionID else { return }
        states[accountID]?.sessionID = nil
        try persist(accountID)
    }

    func setConsent(accountID: UUID, enabled: Bool, now: Date = .now) throws -> DiagnosticCollectionSnapshot {
        _ = try load(accountID: accountID, now: now)
        var state = states[accountID] ?? State()
        state.isEnabled = enabled
        state.consentWasChosen = true
        state.sessionID = UUID()
        if !enabled {
            state.pending = []
            state.report = nil
        }
        try persist(accountID, state: state)
        states[accountID] = state
        return snapshot(accountID)
    }

    func append(accountID: UUID, sessionID: UUID, buildNumber: Int, event: BackendDiagnostics.Event, now: Date = .now) throws {
        guard var state = states[accountID], state.isEnabled, state.sessionID == sessionID,
              buildNumber > 0, Self.accepts(event, now: now) else { return }
        state.pending.append(Captured(sessionID: sessionID, buildNumber: buildNumber, event: event))
        let allowance = Self.maximumEvents - (state.report?.events.count ?? 0)
        if state.pending.count > allowance { state.pending.removeFirst(state.pending.count - allowance) }
        states[accountID] = state
        // Writes coalesce; a force quit may lose the last two seconds of metrics.
        if checkpointTask == nil {
            checkpointTask = Task {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                try? checkpoint()
                checkpointTask = nil
            }
        }
    }

    func checkpoint() throws {
        for accountID in states.keys { try persist(accountID) }
    }

    func prepareReport(accountID: UUID, now: Date = .now) throws -> BackendDiagnosticReport? {
        _ = try load(accountID: accountID, now: now)
        guard var state = states[accountID], state.isEnabled else { return nil }
        if let report = state.report { try persist(accountID); return report }
        guard let first = state.pending.first else { return nil }
        let items = Array(state.pending.prefix(Self.batchSize).prefix {
            $0.sessionID == first.sessionID && $0.buildNumber == first.buildNumber
        })
        let report = BackendDiagnosticReport(reportID: UUID(), sessionID: first.sessionID,
            buildNumber: first.buildNumber, events: items.map(\.event))
        state.pending.removeFirst(items.count)
        state.report = report
        states[accountID] = state
        try persist(accountID) // Stable payload/ID survives failed uploads and relaunch.
        return report
    }

    func acknowledge(accountID: UUID, reportID: UUID, now: Date = .now) throws -> DiagnosticCollectionSnapshot {
        if states[accountID]?.report?.reportID == reportID {
            states[accountID]?.report = nil
            states[accountID]?.lastUploadedAt = now
            try persist(accountID)
        }
        return snapshot(accountID)
    }

    private func snapshot(_ accountID: UUID) -> DiagnosticCollectionSnapshot {
        let state = states[accountID] ?? State()
        return DiagnosticCollectionSnapshot(isEnabled: state.isEnabled, sessionID: state.sessionID,
            queuedCount: state.pending.count + (state.report?.events.count ?? 0), lastUploadedAt: state.lastUploadedAt)
    }
    private func prune(_ accountID: UUID, now: Date) {
        guard var state = states[accountID] else { return }
        state.pending.removeAll { !Self.accepts($0.event, now: now) }
        if let report = state.report, !report.events.allSatisfy({ Self.accepts($0, now: now) }) { state.report = nil }
        states[accountID] = state
    }
    private static func accepts(_ event: BackendDiagnostics.Event, now: Date) -> Bool {
        guard event.startedAt >= now.addingTimeInterval(-localLifetime), event.startedAt <= now.addingTimeInterval(300),
              let duration = event.durationMilliseconds, duration.isFinite, duration >= 0, duration <= 3_600_000 else { return false }
        if event.kind == .stage {
            guard event.stage != nil, event.requestKind == nil, event.httpStatus == nil,
                  event.transportErrorCode == nil, event.payloadBytes == nil, event.receivedBytes == nil else { return false }
        } else { guard event.requestKind != nil, event.stage == nil else { return false } }
        if let status = event.httpStatus, !(100...599).contains(status) { return false }
        if let code = event.transportErrorCode, !(-200000...0).contains(code) { return false }
        return [event.payloadBytes, event.receivedBytes].allSatisfy { $0.map { (0...1_073_741_824).contains($0) } ?? true }
    }
    private func file(_ accountID: UUID) -> URL { root.appendingPathComponent(accountID.uuidString).appendingPathExtension("json") }
    private func persist(_ accountID: UUID, state suppliedState: State? = nil) throws {
        guard let state = suppliedState ?? states[accountID] else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: file(accountID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var resource = file(accountID)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}

protocol BackendDiagnosticUploading: Sendable {
    func upload(_ report: BackendDiagnosticReport, accountID: UUID) async throws
}

struct SupabaseDiagnosticUploader: BackendDiagnosticUploading {
    let client: SupabaseClient
    let configuration: BackendConfiguration
    var session: URLSession = .shared
    func upload(_ report: BackendDiagnosticReport, accountID: UUID) async throws {
        let authSession = try await client.auth.session
        guard authSession.user.id == accountID else { throw CancellationError() }
        try Task.checkCancellation()
        // Pin the captured account's JWT for this request. Auth changes cannot relabel
        // an old account's queued data as a different user. No JWT is persisted/logged.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let transport = PostgrestClient(url: configuration.supabaseURL.appendingPathComponent("rest/v1"),
            headers: ["apikey": configuration.publishableKey, "Authorization": "Bearer \(authSession.accessToken)"],
            fetch: { [session] in try await session.data(for: $0) }, encoder: encoder)
        struct Params: Encodable, Sendable {
            let p_report_id: UUID; let p_session_id: UUID; let p_build_number: Int
            let p_events: [BackendDiagnostics.Event]
        }
        // Intentionally uninstrumented: collection cannot create its own diagnostics.
        let accepted: Int = try await transport.rpc("ingest_backend_diagnostics", params: Params(
            p_report_id: report.reportID, p_session_id: report.sessionID,
            p_build_number: report.buildNumber, p_events: report.events)).execute().value
        guard accepted == report.events.count else { throw URLError(.badServerResponse) }
    }
}

@MainActor @Observable
final class DiagnosticCollectionController {
    private let store: BackendDiagnosticStore
    private let uploader: (any BackendDiagnosticUploading)?
    private let diagnostics: BackendDiagnostics
    private let buildNumber: Int
    private var accountID: UUID?
    private var sessionID: UUID?
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var uploadTask: Task<Void, any Error>?
    private var lastAttempt: Date?
    private var isForeground = true
    private var storagePaused = false
    private(set) var isEnabled = false
    private(set) var isSending = false
    private(set) var queuedCount = 0
    private(set) var lastUploadedAt: Date?
    private(set) var status: String?
    var uploadsRemotely: Bool { uploader != nil }
    var startsEnabledByDefault: Bool { store.defaultsToEnabled }

    init(store: BackendDiagnosticStore = BackendDiagnosticStore(), uploader: (any BackendDiagnosticUploading)? = nil,
         diagnostics: BackendDiagnostics = .shared,
         buildNumber: Int = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1) {
        self.store = store; self.uploader = uploader; self.diagnostics = diagnostics; self.buildNumber = buildNumber
    }

    func activate(accountID: UUID) async {
        if self.accountID == accountID { return }
        deactivate()
        self.accountID = accountID
        let scope = generation
        do {
            let snapshot = try await store.beginSession(accountID: accountID)
            guard generation == scope else { return }
            apply(snapshot)
            installCapture(snapshot)
        } catch {
            if generation == scope {
                storagePaused = true
                isEnabled = false
                status = "Diagnostic storage couldn’t open. Collection is paused; try enabling sharing again."
            }
        }
    }

    func deactivate() {
        diagnostics.setCollectionSink(nil)
        worker?.cancel(); worker = nil
        uploadTask?.cancel(); uploadTask = nil
        if let accountID, let sessionID { Task { try? await store.endSession(accountID: accountID, sessionID: sessionID) } }
        generation = UUID(); accountID = nil; lastAttempt = nil
        sessionID = nil; storagePaused = false
        isEnabled = false; isSending = false; queuedCount = 0; lastUploadedAt = nil; status = nil
    }

    func setEnabled(_ enabled: Bool) async {
        guard let accountID else { return }
        diagnostics.setCollectionSink(nil)
        worker?.cancel(); worker = nil; uploadTask?.cancel()
        generation = UUID(); let scope = generation
        do {
            let snapshot = try await store.setConsent(accountID: accountID, enabled: enabled)
            guard generation == scope else { return }
            storagePaused = false
            isSending = false; apply(snapshot); status = nil; installCapture(snapshot)
        } catch {
            if generation == scope {
                storagePaused = true
                if let sessionID { try? await store.endSession(accountID: accountID, sessionID: sessionID) }
                guard generation == scope else { return }
                isEnabled = false; isSending = false; uploadTask = nil
                status = "Diagnostic settings couldn’t save. Collection is paused for now; try again before closing manna."
            }
        }
    }

    func refreshSummary() async {
        guard let accountID else { return }
        let scope = generation
        if let snapshot = try? await store.load(accountID: accountID), scope == generation {
            if storagePaused { queuedCount = snapshot.queuedCount; lastUploadedAt = snapshot.lastUploadedAt }
            else { apply(snapshot) }
        }
    }

    func sendNow(now: Date = .now, automatic: Bool = false) async {
        guard isEnabled, isForeground, !isSending, let accountID, let uploader else { return }
        let spacing: TimeInterval = automatic ? 300 : 60
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < spacing {
            if !automatic { status = "Please wait a minute before sending another batch." }
            return
        }
        let scope = generation
        isSending = true
        defer { if scope == generation { isSending = false; uploadTask = nil } }
        do {
            let prepared = try await store.prepareReport(accountID: accountID, now: now)
            guard scope == generation, isEnabled, isForeground, !Task.isCancelled else { return }
            guard let report = prepared else {
                if !automatic { status = "No queued diagnostic records yet." }; return
            }
            lastAttempt = now
            let task = Task { try await uploader.upload(report, accountID: accountID) }
            uploadTask = task
            try await task.value
            guard scope == generation, isEnabled else { return }
            let snapshot = try await store.acknowledge(accountID: accountID, reportID: report.reportID, now: now)
            guard scope == generation, isEnabled else { return }
            apply(snapshot)
            status = "Diagnostic batch sent."
        } catch {
            guard scope == generation else { return }
            status = "Diagnostics couldn’t send. Queued records will retry while manna is open."
        }
    }

    private func apply(_ snapshot: DiagnosticCollectionSnapshot) {
        isEnabled = snapshot.isEnabled; sessionID = snapshot.sessionID
        queuedCount = snapshot.queuedCount; lastUploadedAt = snapshot.lastUploadedAt
    }
    private func installCapture(_ snapshot: DiagnosticCollectionSnapshot) {
        guard snapshot.isEnabled, let accountID, let sessionID = snapshot.sessionID else { return }
        let store = store; let buildNumber = buildNumber
        diagnostics.setCollectionSink { event in
            Task { try? await store.append(accountID: accountID, sessionID: sessionID, buildNumber: buildNumber, event: event) }
        }
        startWorker()
    }

    func setForeground(_ active: Bool) {
        isForeground = active
        worker?.cancel(); worker = nil
        if !active { uploadTask?.cancel(); Task { try? await store.checkpoint() } }
        else if isEnabled { startWorker() }
    }

    private func startWorker() {
        guard isForeground else { return }
        worker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                guard let self, self.isEnabled else { return }
                await self.sendNow(automatic: true)
            }
        }
    }
}
