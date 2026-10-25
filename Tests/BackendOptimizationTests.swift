import XCTest
import Supabase
@testable import BlessingCircle

final class BackendOptimizationTests: XCTestCase {
    func testDeviceRegistrationSendsNullForEitherUnavailableToken() async throws {
        let fixture = try BackendHTTPFixture()
        defer { fixture.close() }
        let installationID = UUID()
        for (apns, activity) in [("synthetic-apns", nil), (nil, "synthetic-activity"),
                                 ("synthetic-apns", "synthetic-activity")] as [(String?, String?)] {
            try await fixture.repository.registerDevice(installationID: installationID,
                apnsToken: apns, pushToStartToken: activity, environment: "production")
            let body = try XCTUnwrap(fixture.lastRegistrationBody)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(payload.keys), ["p_installation_id", "p_apns_token", "p_push_to_start_token", "p_environment"])
            XCTAssertEqual(payload["p_installation_id"] as? String, installationID.uuidString)
            XCTAssertEqual(payload["p_environment"] as? String, "production")
            if let apns { XCTAssertEqual(payload["p_apns_token"] as? String, apns) }
            else { XCTAssertTrue(payload["p_apns_token"] is NSNull) }
            if let activity { XCTAssertEqual(payload["p_push_to_start_token"] as? String, activity) }
            else { XCTAssertTrue(payload["p_push_to_start_token"] is NSNull) }
        }
        XCTAssertEqual(fixture.requestPaths, Array(repeating: "/rest/v1/rpc/register_device", count: 3))
    }

    func testLocalMetadataOverloadsPreserveTimelineAndPaging() async throws {
        let now = Date()
        let repository: any BlessingRepository = LocalBlessingRepository(now: now)
        let bootstrap = try await repository.bootstrap()
        for circle in bootstrap.circles {
            let byID = try await repository.timeline(circleID: circle.id, viewerID: bootstrap.currentUser.id, now: now)
            let byMetadata = try await repository.timeline(circle: circle, viewerID: bootstrap.currentUser.id, now: now)
            XCTAssertEqual(byMetadata, byID)
            let pageByID = try await repository.timelinePage(circleID: circle.id,
                viewerID: bootstrap.currentUser.id, now: now, before: nil)
            let pageByMetadata = try await repository.timelinePage(circle: circle,
                viewerID: bootstrap.currentUser.id, now: now, before: nil)
            XCTAssertEqual(pageByMetadata.lanes, pageByID.lanes)
            XCTAssertEqual(pageByMetadata.nextBeforeDate, pageByID.nextBeforeDate)
        }
    }

    func testHostedMetadataReuseRemovesFiveRequestsWithoutCachingTimeline() async throws {
        let fixture = try BackendHTTPFixture()
        defer { fixture.close() }
        let repository: any BlessingRepository = fixture.repository
        let context = try await repository.circleContext(circleID: fixture.circleID)
        fixture.resetRequests()
        let baseline = try await repository.timelinePage(circleID: fixture.circleID,
            viewerID: fixture.viewerID, now: fixture.now, before: nil)
        XCTAssertEqual(fixture.requestPaths.count, 7)
        XCTAssertEqual(fixture.metadataRequestCount, 5)

        fixture.resetRequests()
        let optimized = try await repository.timelinePage(circle: context.circle,
            viewerID: fixture.viewerID, now: fixture.now, before: nil)
        XCTAssertEqual(optimized.lanes, baseline.lanes)
        XCTAssertEqual(optimized.nextBeforeDate, baseline.nextBeforeDate)
        XCTAssertEqual(fixture.requestPaths, ["/rest/v1/daily_prompts", "/rest/v1/blessings"])
        XCTAssertEqual(fixture.metadataRequestCount, 0)
        XCTAssertTrue(optimized.lanes.first { $0.member.id == fixture.peerID }?.events.contains {
            $0.status == .locked
        } == true)

        // The next refresh must ask the backend again so a new viewer post can unlock peers.
        fixture.viewerHasSubmitted = true
        fixture.resetRequests()
        let updated = try await repository.timelinePage(circle: context.circle,
            viewerID: fixture.viewerID, now: fixture.now, before: nil)
        XCTAssertEqual(fixture.requestPaths, ["/rest/v1/daily_prompts", "/rest/v1/blessings"])
        XCTAssertTrue(updated.lanes.first { $0.member.id == fixture.peerID }?.events.contains {
            if case .blessing = $0.status { return true }; return false
        } == true)
        XCTAssertFalse(updated.lanes.first { $0.member.id == fixture.peerID }?.events.contains {
            $0.status == .locked
        } == true)
    }

    func testSavedFilesBypassSigningAndOtherRefreshesReuseLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedBlessingStore(root: root)
        let fixture = try BackendHTTPFixture(savedStore: store)
        defer { fixture.close() }
        fixture.viewerHasSubmitted = true
        fixture.includesAudio = true
        let context = try await fixture.repository.circleContext(circleID: fixture.circleID)
        fixture.resetRequests()
        let first = try await fixture.repository.timelinePage(circle: context.circle, viewerID: fixture.viewerID, now: fixture.now, before: nil)
        XCTAssertEqual(fixture.requestPaths.filter { $0.contains("/object/sign/") }.count, 2)
        fixture.resetRequests()
        _ = try await fixture.repository.timelinePage(circle: context.circle, viewerID: fixture.viewerID, now: fixture.now, before: nil)
        XCTAssertEqual(fixture.requestPaths.filter { $0.contains("/object/sign/") }.count, 0)
        XCTAssertEqual(fixture.requestPaths.filter { $0 == "/rest/v1/blessings" }.count, 1, "Authorization stays fresh")
        let source = root.appendingPathComponent("fixture.caf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("local bytes".utf8).write(to: source)
        for lane in first.lanes {
            for event in lane.events {
                guard case let .blessing(blessing) = event.status else { continue }
                _ = try await store.save(blessing: blessing.replacingMedia(audio: source, video: nil, photo: nil),
                    responses: [], userID: fixture.viewerID)
            }
        }
        let reopened = SupabaseBlessingRepository(client: fixture.client, savedStore: store)
        fixture.resetRequests()
        let local = try await reopened.timelinePage(circle: context.circle, viewerID: fixture.viewerID, now: fixture.now, before: nil)
        XCTAssertFalse(local.lanes.flatMap(\.events).compactMap { event -> URL? in
            if case let .blessing(value) = event.status { return value.audioURL }; return nil
        }.contains { !$0.isFileURL })
        XCTAssertEqual(fixture.requestPaths.filter { $0.contains("/object/sign/") }.count, 0)
    }

    func testHostedMetadataReuseStillPropagatesAuthorizationFailure() async throws {
        let fixture = try BackendHTTPFixture()
        defer { fixture.close() }
        let context = try await fixture.repository.circleContext(circleID: fixture.circleID)
        fixture.denyBlessings = true
        do {
            _ = try await fixture.repository.timelinePage(circle: context.circle,
                viewerID: fixture.viewerID, now: fixture.now, before: nil)
            XCTFail("Reusing circle metadata must not replace a failed authorized content read with cached data")
        } catch {
            XCTAssertTrue(fixture.requestPaths.contains("/rest/v1/blessings"))
        }
    }

    func testHostedUnpagedMetadataOverloadAlsoFetchesFreshContent() async throws {
        let fixture = try BackendHTTPFixture()
        defer { fixture.close() }
        let context = try await fixture.repository.circleContext(circleID: fixture.circleID)
        fixture.resetRequests()
        let repository: any BlessingRepository = fixture.repository
        _ = try await repository.timeline(circle: context.circle, viewerID: fixture.viewerID, now: fixture.now)
        XCTAssertEqual(fixture.requestPaths, ["/rest/v1/daily_prompts", "/rest/v1/blessings"])
    }
}

/// Everything uses a private URLSession, synthetic identity, and reserved .invalid host.
/// This fixture verifies adapter requests and presentation; it does not emulate server RLS.
private final class BackendHTTPFixture: @unchecked Sendable {
    let circleID = UUID()
    let viewerID = UUID()
    let peerID = UUID()
    let promptID = UUID()
    let peerBlessingID = UUID()
    let viewerBlessingID = UUID()
    let now = Date()
    let host = "backend-test-\(UUID().uuidString.lowercased()).invalid"
    private let lock = NSLock()
    private var paths: [String] = []
    private var hasSubmitted = false
    private var denied = false
    private var registrationBody: Data?
    var lastRegistrationBody: Data? { lock.withLock { registrationBody } }
    var includesAudio = false
    private(set) var client: SupabaseClient!
    private var session: URLSession!
    private(set) var repository: SupabaseBlessingRepository!

    var viewerHasSubmitted: Bool {
        get { lock.withLock { hasSubmitted } }
        set { lock.withLock { hasSubmitted = newValue } }
    }
    var denyBlessings: Bool {
        get { lock.withLock { denied } }
        set { lock.withLock { denied = newValue } }
    }
    var requestPaths: [String] { lock.withLock { paths } }
    var metadataRequestCount: Int {
        requestPaths.filter { ["circles", "circle_members", "profiles", "circle_invite_code", "circle_streaks"].contains(URL(fileURLWithPath: $0).lastPathComponent) }.count
    }
    func resetRequests() { lock.withLock { paths = [] } }

    init(savedStore: SavedBlessingStore = SavedBlessingStore()) throws {
        let storage = BackendTestAuthStorage()
        let user = User(id: viewerID, appMetadata: [:], userMetadata: [:], aud: "authenticated",
            createdAt: now, updatedAt: now)
        let authSession = Session(accessToken: "synthetic-test-token", tokenType: "bearer", expiresIn: 3600,
            expiresAt: now.addingTimeInterval(3600).timeIntervalSince1970,
            refreshToken: "synthetic-refresh-token", user: user)
        try storage.store(key: "test-session", value: JSONEncoder().encode(authSession))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendTestURLProtocol.self]
        session = URLSession(configuration: configuration)
        BackendTestURLProtocol.register(self)
        client = SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "synthetic-key",
            options: .init(auth: .init(storage: storage, storageKey: "test-session", autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true), global: .init(session: session)))
        repository = SupabaseBlessingRepository(client: client, savedStore: savedStore)
    }

    func close() {
        session.invalidateAndCancel()
        BackendTestURLProtocol.unregister(host: host)
    }

    func response(for request: URLRequest) throws -> (Int, Data) {
        let url = try XCTUnwrap(request.url)
        lock.withLock { paths.append(url.path) }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: now.addingTimeInterval(-60))
        let joinedAt = formatter.string(from: now.addingTimeInterval(-86400 * 30))
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let prompt: [String: Any] = ["id": promptID.uuidString, "circle_id": circleID.uuidString,
            "local_date": dateFormatter.string(from: now), "starts_at": timestamp,
            "ends_at": formatter.string(from: now.addingTimeInterval(540)), "kind": "daily", "state": "started"]
        let value: Any
        if url.path.contains("/storage/v1/object/sign/") {
            return (200, Data("{\"signedURL\":\"/object/sign/blessing-media/voice.caf?token=fixture\"}".utf8))
        }
        switch url.path {
        case "/rest/v1/rpc/register_device":
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                var data = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                body = data
            }
            let data = try XCTUnwrap(body)
            lock.withLock { registrationBody = data }
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            // Match the deployed function's four required argument names.
            guard Set(payload.keys) == ["p_installation_id", "p_apns_token", "p_push_to_start_token", "p_environment"] else {
                return (404, Data(#"{"code":"PGRST202","message":"Function signature not found"}"#.utf8))
            }
            value = NSNull()
        case "/rest/v1/circles":
            value = ["id": circleID.uuidString, "name": "Fixture", "owner_id": viewerID.uuidString,
                "time_zone": "UTC", "window_start": "09:00:00", "window_end": "18:00:00",
                "response_window_minutes": 10, "allow_late_blessings": true,
                "repeat_window_minutes": 60, "end_of_day_time": "20:00:00"]
        case "/rest/v1/circle_members":
            value = [viewerID, peerID].map { ["circle_id": circleID.uuidString, "user_id": $0.uuidString, "joined_at": joinedAt] }
        case "/rest/v1/profiles":
            value = [viewerID, peerID].map { ["id": $0.uuidString, "display_name": "Fixture member", "bible_version_id": "web"] }
        case "/rest/v1/rpc/circle_invite_code": value = NSNull()
        case "/rest/v1/rpc/circle_streaks": value = [Any]()
        case "/rest/v1/rpc/first_join_blessing_prompt": value = NSNull()
        case "/rest/v1/daily_prompts":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            value = items.contains { $0.name == "kind" && $0.value == "eq.end_of_day" } ? [] : [prompt]
        case "/rest/v1/blessings":
            if denyBlessings {
                return (403, Data(#"{"code":"42501","message":"permission denied"}"#.utf8))
            }
            func blessing(_ id: UUID, author: UUID) -> [String: Any] {
                ["id": id.uuidString, "prompt_id": promptID.uuidString, "author_id": author.uuidString,
                 "capture_mode": includesAudio ? "voice" : "typed", "body": "Synthetic fixture text", "submitted_at": timestamp, "is_late": false,
                 "audio_path": includesAudio ? "voice-\(id).caf" : NSNull()]
            }
            var rows = [blessing(peerBlessingID, author: peerID)]
            if viewerHasSubmitted { rows.append(blessing(viewerBlessingID, author: viewerID)) }
            value = rows
        default:
            throw URLError(.unsupportedURL)
        }
        return (200, try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
    }
}

private final class BackendTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private final class BackendTestURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: BackendHTTPFixture] = [:]
    }
    private static let registry = Registry()
    static func register(_ fixture: BackendHTTPFixture) {
        registry.lock.withLock { registry.fixtures[fixture.host] = fixture }
    }
    static func unregister(host: String) {
        _ = registry.lock.withLock { registry.fixtures.removeValue(forKey: host) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url,
                  let fixture = Self.registry.lock.withLock({ Self.registry.fixtures[url.host ?? ""] }) else {
                throw URLError(.unsupportedURL)
            }
            let (status, data) = try fixture.response(for: request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
