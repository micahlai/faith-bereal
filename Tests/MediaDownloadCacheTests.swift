import XCTest
@testable import BlessingCircle

final class MediaDownloadCacheTests: XCTestCase {
    func testRenewedLinksRelaunchAndAccountIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), other = UUID(), probe = CacheDownloadProbe()
        let first = URL(string: "https://cache.invalid/storage/v1/object/sign/media/audio.caf?token=one")!
        let renewed = URL(string: "https://cache.invalid/storage/v1/object/sign/media/audio.caf?token=two")!
        let cache = MediaDownloadCache(root: root)
        let file = try await cache.file(for: first, accountID: account, download: probe.download)
        let second = try await cache.file(for: renewed, accountID: account, download: probe.download)
        XCTAssertEqual(file, second)
        let reopened = MediaDownloadCache(root: root)
        _ = try await reopened.file(for: renewed, accountID: account, download: probe.download)
        let missing = await reopened.cachedFile(for: renewed, accountID: other)
        XCTAssertNil(missing)
        _ = try await reopened.file(for: renewed, accountID: other, download: probe.download)
        let count = await probe.count
        XCTAssertEqual(count, 2)
        let data = try Data(contentsOf: file)
        XCTAssertEqual(data.count, 32)
        XCTAssertTrue(try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    func testSavingPlayedMediaCopiesCacheIntoIndependentPermanentArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), probe = CacheDownloadProbe()
        let url = URL(string: "https://cache.invalid/\(UUID().uuidString).m4a?token=one")!
        _ = try await MediaDownloadCache.shared.file(for: url, accountID: account, download: probe.download)
        let renewed = URL(string: url.absoluteString.replacingOccurrences(of: "token=one", with: "token=two"))!
        let store = SavedBlessingStore(root: root, copier: CachedFileOnlyCopier())
        let blessing = Blessing(id: UUID(), circleID: UUID(), promptID: UUID(), authorID: account,
            captureMode: .voice, body: "Cached recording", audioURL: renewed, videoURL: nil,
            submittedAt: .now, isLate: false, scriptureReference: nil)
        let saved = try await store.save(blessing: blessing, responses: [], userID: account)
        await MediaDownloadCache.shared.clear(accountID: account)
        let file = try XCTUnwrap(saved.blessing.audioURL)
        XCTAssertTrue(file.isFileURL)
        XCTAssertEqual(try Data(contentsOf: file).count, 32, "Permanent Save must survive temporary-cache removal")
        let reopened = await SavedBlessingStore(root: root).loadRecord(blessingID: blessing.id, userID: account)
        XCTAssertEqual(reopened?.blessing.audioURL, file)
        let count = await probe.count
        XCTAssertEqual(count, 1)
    }

    func testConcurrentLoadsShareDownloadAndSignOutFencesLateResult() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = MediaDownloadCache(root: root), probe = CacheDownloadProbe(suspended: true), account = UUID()
        let url = URL(string: "https://cache.invalid/voice.caf")!
        let first = Task { try await cache.file(for: url, accountID: account, download: probe.download) }
        while await probe.count == 0 { await Task.yield() }
        let second = Task { try await cache.file(for: url, accountID: account, download: probe.download) }
        await Task.yield()
        await probe.release()
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a, b)
        let count = await probe.count
        XCTAssertEqual(count, 1)
        let slow = CacheDownloadProbe(suspended: true)
        let nextURL = URL(string: "https://cache.invalid/another.caf")!
        let late = Task { try await cache.file(for: nextURL, accountID: account, download: slow.download) }
        while await slow.count == 0 { await Task.yield() }
        await cache.clear(accountID: account)
        await slow.release()
        do { _ = try await late.value; XCTFail("Signed-out download installed") } catch { }
        let missing = await cache.cachedFile(for: nextURL, accountID: account)
        XCTAssertNil(missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }

    func testExpiryEvictionAndFailuresDoNotBecomePermanentSaves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = CacheTestClock(), cache = MediaDownloadCache(root: root, maximumBytes: 40, lifetime: 60, now: clock.read)
        let probe = CacheDownloadProbe(), account = UUID()
        let a = URL(string: "https://cache.invalid/a.m4a")!, b = URL(string: "https://cache.invalid/b.mp4")!
        _ = try await cache.file(for: a, accountID: account, download: probe.download)
        clock.advance(1)
        _ = try await cache.file(for: b, accountID: account, download: probe.download)
        let evicted = await cache.cachedFile(for: a, accountID: account)
        XCTAssertNil(evicted)
        clock.advance(61)
        let expired = await cache.cachedFile(for: b, accountID: account)
        XCTAssertNil(expired)
        await probe.setStatus(503)
        do { _ = try await cache.file(for: a, accountID: account, download: probe.download); XCTFail("Accepted HTTP failure") } catch { }
        let failed = await cache.cachedFile(for: a, accountID: account)
        XCTAssertNil(failed)
        await probe.setStatus(200)
        _ = try await cache.file(for: a, accountID: account, download: probe.download)
        let count = await probe.count
        XCTAssertEqual(count, 4)
    }
}

private actor CacheDownloadProbe {
    var count = 0
    var status = 200
    var suspended: Bool
    var continuation: CheckedContinuation<Void, Never>?
    init(suspended: Bool = false) { self.suspended = suspended }
    func setStatus(_ value: Int) { status = value }
    func release() { suspended = false; continuation?.resume(); continuation = nil }
    func download(_ url: URL) async throws -> (URL, URLResponse) {
        count += 1
        if suspended { await withCheckedContinuation { continuation = $0 } }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 1, count: 32).write(to: file)
        return (file, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private final class CacheTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date()
    func read() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

private struct CachedFileOnlyCopier: SavedBlessingMediaCopying {
    func copy(from source: URL, to destination: URL) async throws {
        guard source.isFileURL else { throw URLError(.badURL) }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
