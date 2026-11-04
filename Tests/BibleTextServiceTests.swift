import XCTest
@testable import BlessingCircle

final class BibleTextServiceTests: XCTestCase {
    private static let reviewedCredit = "World English Bible (WEB)\nPublic Domain (CC0).\nThe World English Bible has been dedicated to the public domain by its translators and may be freely used and distributed."

    private let john = BibleBook.all.first { $0.slug == "john" }!
    private var reference: ScriptureReference {
        .init(bookSlug: "john", bookName: "John", chapter: 3, verseStart: 16, verseEnd: 17)
    }

    func testReviewedCatalogExcludesLicensedUnresolvedAndTerritoryRestrictedVersions() {
        let expected: Set<String> = ["web", "bsb", "asv", "ylt", "dra", "bbe", "geneva1599", "rvr1909", "svd", "synodal", "luth1912", "riveduta"]
        XCTAssertEqual(Set(BibleTranslation.publicDomain.map(\.id)), expected)
        for removed in ["lsg", "almeida-livre", "kjv", "cuv", "cuvs", "kgy", "kor", "vi1934", "niv", "esv", "unknown", "WEB", ""] {
            XCTAssertFalse(BibleTranslation.supports(removed), removed)
            XCTAssertEqual(BibleTranslation.selection(for: removed).id, BibleTranslation.defaultVersionID)
        }
        for version in expected { XCTAssertEqual(BibleTranslation.selection(for: version).id, version) }
        XCTAssertEqual(BibleTranslation.selection(for: nil).id, "web")
    }

    func testRemovedVersionCannotMakeARequestEvenWhenDirectlyPassedToService() async throws {
        let fixture = BibleHTTPFixture(responses: [try envelope()]); defer { fixture.close() }
        let service = BibleAPIService(session: fixture.session)
        for removed in ["lsg", "almeida-livre", "kjv", "cuv", "cuvs", "kgy", "kor", "vi1934", "niv"] {
            do { _ = try await service.chapter(versionID: removed, book: john, chapter: 3); XCTFail(removed) }
            catch { XCTAssertTrue(error is BibleTextError) }
            do { _ = try await service.passage(versionID: removed, reference: reference); XCTFail(removed) }
            catch { XCTAssertTrue(error is BibleTextError) }
        }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testChapterCachesMatchingTextAndPreservesProviderCredit() async throws {
        let fixture = BibleHTTPFixture(responses: [try envelope(first: 1, last: 2)]); defer { fixture.close() }
        let service = BibleAPIService(session: fixture.session)
        let chapter = try await service.chapter(versionID: "web", book: john, chapter: 3)
        let cached = try await service.chapter(versionID: "web", book: john, chapter: 3)
        XCTAssertEqual(chapter, cached)
        XCTAssertEqual(chapter.verses, ["First synthetic verse.", "Second synthetic verse."])
        XCTAssertEqual(chapter.credit, Self.reviewedCredit)
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testPassagePreservesVerseNumbersCreditAndPrivateRequestBoundary() async throws {
        let fixture = BibleHTTPFixture(responses: [try envelope()]); defer { fixture.close() }
        let passage = try await BibleAPIService(session: fixture.session).passage(versionID: "web", reference: reference)
        XCTAssertEqual(passage.text, "¹⁶ First synthetic verse.\n¹⁷ Second synthetic verse.")
        XCTAssertEqual(passage.credit, Self.reviewedCredit)
        let request = try XCTUnwrap(fixture.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/web/john/3/16-17")
        XCTAssertEqual(request.url?.query, nil)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testAliasResponseIsRejectedAndDoesNotPoisonChapterCache() async throws {
        let fixture = BibleHTTPFixture(responses: [try envelope(version: "niv", first: 1, last: 2), try envelope(first: 1, last: 2)])
        defer { fixture.close() }
        let service = BibleAPIService(session: fixture.session)
        do { _ = try await service.chapter(versionID: "web", book: john, chapter: 3); XCTFail("Aliased version displayed") }
        catch { XCTAssertTrue(error is BibleTextError) }
        let accepted = try await service.chapter(versionID: "web", book: john, chapter: 3)
        let cached = try await service.chapter(versionID: "web", book: john, chapter: 3)
        XCTAssertEqual(accepted, cached)
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testWrongBookChapterRangeEmptyTextAndMissingCreditCannotBeDisplayed() async throws {
        let invalid = [
            try envelope(version: "bsb"), try envelope(book: "genesis"), try envelope(chapter: 4),
            try envelope(first: 15, last: 16), try envelope(first: 16, last: 18),
            try envelope(verses: ["", " "]), try envelope(credit: ""), try envelope(credit: nil), try envelope(credit: "WEB. CC BY. New terms."),
            try envelope(verses: ["Only one synthetic verse."])
        ]
        for response in invalid {
            let fixture = BibleHTTPFixture(responses: [response]); defer { fixture.close() }
            do { _ = try await BibleAPIService(session: fixture.session).passage(versionID: "web", reference: reference); XCTFail("Unexpected passage displayed") }
            catch { /* A rejected payload must never be formatted/displayed. */ }
            XCTAssertEqual(fixture.requests.count, 1)
        }
    }

    func testInvalidReferencesAreRejectedWithoutNetwork() async throws {
        let fixture = BibleHTTPFixture(responses: [try envelope()]); defer { fixture.close() }
        let service = BibleAPIService(session: fixture.session)
        for chapter in [0, 22] {
            do { _ = try await service.chapter(versionID: "web", book: john, chapter: chapter); XCTFail("Invalid chapter") }
            catch { XCTAssertTrue(error is BibleTextError) }
        }
        let bad = ScriptureReference(bookSlug: "john/../../niv", bookName: "John", chapter: 3, verseStart: 1, verseEnd: 2)
        do { _ = try await service.passage(versionID: "web", reference: bad); XCTFail("Invalid path") }
        catch { XCTAssertTrue(error is BibleTextError) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testHTTPFailureDoesNotPopulateCacheAndRetryCanSucceed() async throws {
        let fixture = BibleHTTPFixture(responses: [try envelope(first: 1, last: 2)], statuses: [503, 200]); defer { fixture.close() }
        let service = BibleAPIService(session: fixture.session)
        do { _ = try await service.chapter(versionID: "web", book: john, chapter: 3); XCTFail("HTTP failure accepted") }
        catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
        _ = try await service.chapter(versionID: "web", book: john, chapter: 3)
        XCTAssertEqual(fixture.requests.count, 2)
    }

    @MainActor
    func testModelRejectsRemovedPreferenceAndPreservesSupportedChoice() async throws {
        let repository = LocalBlessingRepository()
        let model = AppModel(repository: repository, registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        await model.bootstrap()
        await model.updateBibleVersion("bsb")
        XCTAssertEqual(model.selectedBibleTranslation.id, "bsb")
        await model.updateBibleVersion("almeida-livre")
        XCTAssertEqual(model.selectedBibleTranslation.id, "bsb")
        XCTAssertNotNil(model.message)
        let bootstrap = try await repository.bootstrap()
        XCTAssertEqual(bootstrap.currentUser.bibleVersionID, "bsb")
    }

    func testWidgetCreditRoundTripsAndOldSnapshotWithoutCreditStillDecodes() throws {
        var item = BlessingWidgetBlessing(id: UUID(), circleID: UUID(), circleName: "Fixture", authorName: "Reader",
            captureMode: .typed, transcript: "Synthetic post", submittedAt: .now, isFromCurrentCircleDay: false,
            scriptureReference: "John 3:16", scriptureText: "Synthetic verse", bibleVersionName: "WEB")
        item.scriptureCredit = Self.reviewedCredit
        item.bibleVersionID = "web"
        XCTAssertEqual(item.creditedScriptureText, "Synthetic verse")
        let encoded = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(BlessingWidgetBlessing.self, from: encoded), item)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "scriptureCredit")
        old.removeValue(forKey: "bibleVersionID")
        let decoded = try JSONDecoder().decode(BlessingWidgetBlessing.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.scriptureCredit)
        XCTAssertNil(decoded.creditedScriptureText)
        XCTAssertEqual(decoded.scriptureReference, "John 3:16")
        item.bibleVersionID = "kjv"
        XCTAssertNil(item.creditedScriptureText)
        item.bibleVersionID = "unknown"
        XCTAssertNil(item.creditedScriptureText)
        XCTAssertEqual(decoded.scriptureText, "Synthetic verse")
    }

    private func envelope(version: String = "web", book: String = "john", chapter: Int = 3,
                          first: Int = 16, last: Int = 17,
                          verses: [String] = ["First synthetic verse.", "Second synthetic verse."],
                          credit: String? = BibleTextServiceTests.reviewedCredit) throws -> Data {
        var result: [String: Any] = ["data": ["version": version, "book": book, "chapter": chapter,
            "verse": first, "verseEnd": last, "verses": verses]]
        if let credit { result["meta"] = ["copyright": credit] }
        return try JSONSerialization.data(withJSONObject: result)
    }
}

private final class BibleHTTPFixture: @unchecked Sendable {
    let id = UUID().uuidString
    private let lock = NSLock()
    private let responses: [Data]
    private let statuses: [Int]
    private var received: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { received } }
    let session: URLSession

    init(responses: [Data], statuses: [Int] = [200]) {
        self.responses = responses; self.statuses = statuses
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BibleTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Bible-Fixture": id]
        session = URLSession(configuration: configuration)
        BibleTestURLProtocol.register(self)
    }
    func close() { session.invalidateAndCancel(); BibleTestURLProtocol.unregister(id) }
    func response(to request: URLRequest) -> (Data, Int) {
        lock.withLock {
            let index = received.count
            received.append(request)
            return (responses[min(index, responses.count - 1)], statuses[min(index, statuses.count - 1)])
        }
    }
}

private final class BibleTestURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: BibleHTTPFixture] = [:]
    }
    private static let registry = Registry()
    static func register(_ fixture: BibleHTTPFixture) { registry.lock.withLock { registry.fixtures[fixture.id] = fixture } }
    static func unregister(_ id: String) { _ = registry.lock.withLock { registry.fixtures.removeValue(forKey: id) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Bible-Fixture"),
              let fixture = Self.registry.lock.withLock({ Self.registry.fixtures[id] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let (data, status) = fixture.response(to: request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
