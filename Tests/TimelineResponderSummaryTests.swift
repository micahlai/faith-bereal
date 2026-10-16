import XCTest
import Supabase
@testable import BlessingCircle

final class TimelineResponderSummaryTests: XCTestCase {
    func testConcurrentCardsBatchDeduplicateAndCacheEmptyResultsWithoutFetchingResponseMedia() async throws {
        let cache = TimelineResponderSummaryCache(delay: .milliseconds(40))
        let probe = SummaryProbe()
        let first = UUID(), second = UUID(), author = UUID(), secondAuthor = UUID()
        await probe.setRows([.init(blessingID: first, authorID: author), .init(blessingID: first, authorID: author),
                             .init(blessingID: first, authorID: secondAuthor), .init(blessingID: UUID(), authorID: UUID())])
        async let a = cache.summary(for: first) { try await probe.load($0) }
        async let b = cache.summary(for: first) { try await probe.load($0) }
        async let c = cache.summary(for: second) { try await probe.load($0) }
        let values = try await [a, b, c]
        let expected = TimelineResponseSummary(count: 3, authorIDs: [author, secondAuthor].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(values, [expected, expected, .empty])
        _ = try await cache.summary(for: second) { try await probe.load($0) }
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(Set(calls[0]), Set([first, second]))
    }

    func testOnlyVoiceMetadataContributesExpiryDatesWhileEveryResponseCounts() async throws {
        let cache = TimelineResponderSummaryCache(delay: .zero)
        let blessing = UUID(), author = UUID()
        let voiceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let typedDate = voiceDate.addingTimeInterval(-86_400)
        let summary = try await cache.summary(for: blessing) { _ in
            [.init(blessingID: blessing, authorID: author, mode: .voice, submittedAt: voiceDate),
             .init(blessingID: blessing, authorID: author, mode: .typed, submittedAt: typedDate)]
        }
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.authorIDs, [author])
        XCTAssertEqual(summary.responseAudioDates, [voiceDate])
        XCTAssertEqual(MediaRetentionPolicy.warning(for: try XCTUnwrap(summary.responseAudioDates.first),
            at: voiceDate.addingTimeInterval(MediaRetentionPolicy.lifetime - 3_600)), "Media expires in 1h")
    }

    func testCancellationRemovesOnlyTheCancelledWaiter() async throws {
        let cache = TimelineResponderSummaryCache(delay: .milliseconds(100))
        let probe = SummaryProbe(), blessing = UUID(), author = UUID()
        await probe.setRows([.init(blessingID: blessing, authorID: author)])
        let cancelled = Task { try await cache.summary(for: blessing) { try await probe.load($0) } }
        let sibling = Task { try await cache.summary(for: blessing) { try await probe.load($0) } }
        try await Task.sleep(for: .milliseconds(10))
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("A cancelled waiter must not receive another card's result") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let actual = try await sibling.value
        XCTAssertEqual(actual, .init(count: 1, authorIDs: [author]))
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testFailuresRetryAndExpiredAndEvictedSummariesReload() async throws {
        let cache = TimelineResponderSummaryCache(capacity: 1, delay: .zero)
        let probe = SummaryProbe(), first = UUID(), second = UUID()
        await probe.setFails(true)
        do { _ = try await cache.summary(for: first) { try await probe.load($0) }; XCTFail("Expected failure") }
        catch {}
        await probe.setFails(false)
        _ = try await cache.summary(for: first) { try await probe.load($0) }
        _ = try await cache.summary(for: first, now: Date().addingTimeInterval(61)) { try await probe.load($0) }
        _ = try await cache.summary(for: second) { try await probe.load($0) }
        _ = try await cache.summary(for: first) { try await probe.load($0) }
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 5)
    }

    func testBatchSizeRemainsBoundedForLargeVisibleSets() async throws {
        let cache = TimelineResponderSummaryCache(delay: .milliseconds(40))
        let probe = SummaryProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<85 {
                group.addTask { _ = try? await cache.summary(for: UUID()) { try await probe.load($0) } }
            }
        }
        let calls = await probe.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertTrue(calls.allSatisfy { $0.count <= 40 })
        XCTAssertEqual(calls.flatMap { $0 }.count, 85)
    }

    func testHostedSummaryUsesOnlyIdentityColumnsAndNoBlessingOrStorageRequest() async throws {
        let fixture = SummaryHTTPFixture()
        defer { fixture.close() }
        let blessing = UUID(), author = UUID()
        fixture.rows = [["blessing_id": blessing.uuidString, "author_id": author.uuidString]]
        let values = try await fixture.repository.timelineResponderSummaries(blessingIDs: [blessing, blessing], viewerID: UUID())
        XCTAssertEqual(values, [.init(blessingID: blessing, authorID: author)])
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/rest/v1/blessing_responses")
        let query = URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "select" }?.value, "blessing_id,author_id,mode,submitted_at")
        let filter = try XCTUnwrap(query.first { $0.name == "blessing_id" }?.value)
        XCTAssertEqual(filter.lowercased(), "in.(\(blessing.uuidString.lowercased()))")
        XCTAssertNil(requests[0].httpBody)
        _ = try await fixture.repository.timelineResponderSummaries(blessingIDs: [], viewerID: UUID())
        XCTAssertEqual(fixture.requests.count, 1)
    }

    @MainActor
    func testLateSummaryCannotReturnAcrossAccountChangeOrPopulateTheNewCache() async throws {
        let fixture = SummaryHTTPFixture()
        defer { fixture.close() }
        fixture.responseDelay = 0.2
        let local = LocalBlessingRepository()
        let seed = try await local.bootstrap()
        let circle = try XCTUnwrap(seed.circle)
        let author = seed.currentUser
        let blessing = Blessing(id: UUID(), circleID: circle.id, promptID: UUID(), authorID: author.id,
            captureMode: .typed, body: "Permitted fixture", audioURL: nil, videoURL: nil,
            submittedAt: .now, isLate: false, scriptureReference: nil)
        let warningNow = Date()
        let voiceDate = warningNow.addingTimeInterval(-MediaRetentionPolicy.lifetime + 36 * 3_600)
        fixture.rows = [["blessing_id": blessing.id.uuidString, "author_id": author.id.uuidString,
                         "mode": "voice", "submitted_at": ISO8601DateFormatter().string(from: voiceDate)]]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TimelineScope-\(UUID())")
        let model = AppModel(repository: fixture.repository,
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("drafts")),
            diagnosticCollection: DiagnosticCollectionController(store: BackendDiagnosticStore(root: root.appendingPathComponent("diagnostics"))),
            metadataStore: CircleMetadataStore(directory: root.appendingPathComponent("metadata")),
            registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        defer {
            model.currentUser = nil
            model.circle = nil
            try? FileManager.default.removeItem(at: root)
        }
        model.currentUser = author
        model.circle = circle
        model.lanes = [.init(member: author, events: [.init(memberID: author.id, date: .now, status: .blessing(blessing))])]
        let revision = model.timelineResponderRevision
        let old = Task { await model.timelineResponseSummary(for: blessing, revision: revision) }
        for _ in 0..<100 where fixture.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(fixture.requests.count, 1, "The old request must be in flight before changing accounts")
        model.currentUser = nil
        model.currentUser = author
        let late = await old.value
        XCTAssertNil(late)
        XCTAssertNil(model.responseMediaDates[blessing.id], "A late result must not mutate the new account's expiry metadata")
        let refreshed = await model.timelineResponseSummary(for: blessing, revision: model.timelineResponderRevision)
        XCTAssertEqual(refreshed?.count, 1)
        XCTAssertEqual(refreshed?.authorIDs, [author.id])
        XCTAssertEqual(model.responseMediaDates[blessing.id]?.count, 1)
        XCTAssertEqual(model.mediaExpiryWarning(for: blessing, at: warningNow), "Media expires in 2 days",
            "Typed blessing cards retain the warning for attached voice responses without loading their audio")
        XCTAssertEqual(fixture.requests.count, 2, "A late old-account result cannot populate the replacement cache")
    }

    @MainActor
    func testModelInvalidatesOnRefreshResponseAndScopeChangesAndRejectsOldRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TimelineSummary-\(UUID())")
        let repository = LocalBlessingRepository()
        let bootstrap = try await repository.bootstrap()
        let model = AppModel(repository: repository,
            savedBlessingStore: SavedBlessingStore(root: root.appendingPathComponent("saved")),
            draftStore: BlessingDraftStore(root: root.appendingPathComponent("drafts")),
            diagnosticCollection: DiagnosticCollectionController(store: BackendDiagnosticStore(root: root.appendingPathComponent("diagnostics"))),
            metadataStore: CircleMetadataStore(directory: root.appendingPathComponent("metadata")),
            registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        defer {
            model.currentUser = nil
            model.circle = nil
            try? FileManager.default.removeItem(at: root)
        }
        model.currentUser = bootstrap.currentUser
        model.circle = bootstrap.circle
        model.circles = bootstrap.circles
        try await model.refreshTimeline(freshCircle: bootstrap.circle)
        let blessing = try XCTUnwrap(model.lanes.flatMap(\.events).compactMap { event -> Blessing? in
            if case let .blessing(value) = event.status { return value }; return nil
        }.first)
        let initial = model.timelineResponderRevision
        let before = await model.timelineResponseSummary(for: blessing, revision: initial)
        let submitted = await model.submitResponse(to: blessing, mode: .typed, body: "Summary refresh", audioURL: nil)
        XCTAssertNotNil(submitted)
        XCTAssertNotEqual(model.timelineResponderRevision, initial)
        let stale = await model.timelineResponseSummary(for: blessing, revision: initial)
        XCTAssertNil(stale)
        let updated = await model.timelineResponseSummary(for: blessing, revision: model.timelineResponderRevision)
        XCTAssertTrue(try XCTUnwrap(updated).authorIDs.contains(bootstrap.currentUser.id))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(updated).count, try XCTUnwrap(before).count)
        let responseRevision = model.timelineResponderRevision
        try await model.refreshTimeline(freshCircle: bootstrap.circle)
        XCTAssertNotEqual(model.timelineResponderRevision, responseRevision)
        let refreshRevision = model.timelineResponderRevision
        model.circle = bootstrap.circles.first { $0.id != bootstrap.circle?.id }
        XCTAssertNotEqual(model.timelineResponderRevision, refreshRevision)
        let switched = await model.timelineResponseSummary(for: blessing, revision: model.timelineResponderRevision)
        XCTAssertNil(switched)
        let circleRevision = model.timelineResponderRevision
        model.currentUser = nil
        XCTAssertNotEqual(model.timelineResponderRevision, circleRevision)
    }
}

private actor SummaryProbe {
    private(set) var calls: [[UUID]] = []
    private var rows: [TimelineResponderSummary] = []
    private var fails = false
    func setRows(_ rows: [TimelineResponderSummary]) { self.rows = rows }
    func setFails(_ fails: Bool) { self.fails = fails }
    func load(_ ids: [UUID]) throws -> [TimelineResponderSummary] {
        calls.append(ids)
        if fails { throw URLError(.notConnectedToInternet) }
        return rows
    }
}

private final class SummaryHTTPFixture: @unchecked Sendable {
    let host = "summary-\(UUID().uuidString.lowercased()).invalid"
    let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var storedRows: [[String: String]] = []
    private var storedDelay: TimeInterval = 0
    var responseDelay: TimeInterval {
        get { lock.withLock { storedDelay } }
        set { lock.withLock { storedDelay = newValue } }
    }
    var rows: [[String: String]] {
        get { lock.withLock { storedRows } }
        set { lock.withLock { storedRows = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
    private let session: URLSession
    private(set) var repository: SupabaseBlessingRepository!
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SummaryURLProtocol.self]
        session = URLSession(configuration: configuration)
        SummaryURLProtocol.register(self)
        repository = SupabaseBlessingRepository(client: SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "synthetic-key",
            options: .init(auth: .init(storage: SummaryAuthStorage(), autoRefreshToken: false), global: .init(session: session))))
    }
    func response(_ request: URLRequest) throws -> Data {
        lock.withLock { recorded.append(request) }
        let delay = responseDelay
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return try JSONSerialization.data(withJSONObject: rows)
    }
    func close() { session.invalidateAndCancel(); SummaryURLProtocol.unregister(host) }
}

private final class SummaryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

private final class SummaryURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: SummaryHTTPFixture] = [:]
    }
    private static let registry = Registry()
    static func register(_ fixture: SummaryHTTPFixture) { registry.lock.withLock { registry.fixtures[fixture.host] = fixture } }
    static func unregister(_ host: String) { _ = registry.lock.withLock { registry.fixtures.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let fixture = try XCTUnwrap(Self.registry.lock.withLock { Self.registry.fixtures[url.host ?? ""] })
            let data = try fixture.response(request)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
