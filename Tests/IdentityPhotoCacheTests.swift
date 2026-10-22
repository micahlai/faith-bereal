import XCTest
import UIKit
@testable import BlessingCircle

@MainActor
final class IdentityPhotoCacheTests: XCTestCase {
    func testDiskCacheSurvivesRelaunchAndSeparatesAccountsAndIdentityKinds() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), otherAccount = UUID(), identity = UUID()
        let fetcher = IdentityPhotoFetcher(data: photo(.red))
        let cache = IdentityPhotoCache(directory: root, fetch: fetcher.fetch)
        let url = URL(string: "https://example.invalid/photo?token=private-token")!
        let first = await cache.imageData(accountID: account, key: .member(identity), sourceURL: url, allowNetwork: true)
        XCTAssertNotNil(first)
        let same = await cache.imageData(accountID: account, key: .member(identity), sourceURL: url, allowNetwork: true)
        XCTAssertEqual(first, same)
        let count = await fetcher.count
        XCTAssertEqual(count, 1)

        let relaunched = IdentityPhotoCache(directory: root, fetch: { _ in nil })
        let disk = await relaunched.cachedData(accountID: account, key: .member(identity))
        let other = await relaunched.cachedData(accountID: otherAccount, key: .member(identity))
        let circle = await relaunched.cachedData(accountID: account, key: .circle(identity))
        XCTAssertEqual(disk, first)
        XCTAssertNil(other)
        XCTAssertNil(circle)
        let files = cacheFiles(root)
        XCTAssertEqual(files.count, 1)
        let stored = try Data(contentsOf: XCTUnwrap(files.first))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("private-token"))
        XCTAssertEqual(try files[0].resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testTokenRenewalReusesPhotoUntilContentVersionChanges() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), key = IdentityPhotoCache.Key.member(UUID())
        let fetcher = IdentityPhotoFetcher(data: photo(.red))
        let cache = IdentityPhotoCache(directory: root, fetch: fetcher.fetch)
        let old = URL(string: "https://example.invalid/avatar.jpg?token=one&v=1")!
        let renewed = URL(string: "https://example.invalid/avatar.jpg?token=two&v=1")!
        _ = await cache.imageData(accountID: account, key: key, sourceURL: old, allowNetwork: true)
        _ = await cache.imageData(accountID: account, key: key, sourceURL: renewed, allowNetwork: true)
        let before = await fetcher.count
        XCTAssertEqual(before, 1)
        await fetcher.setData(photo(.blue))
        _ = await cache.imageData(accountID: account, key: key,
            sourceURL: URL(string: "https://example.invalid/avatar.jpg?token=three&v=2")!, allowNetwork: true)
        let after = await fetcher.count
        XCTAssertEqual(after, 2)
    }

    func testCachedMetadataCannotFetchAndFreshURLRefreshesExistingBytes() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), member = IdentityPhotoCache.Key.member(UUID())
        let fetcher = IdentityPhotoFetcher(data: photo(.red))
        let cache = IdentityPhotoCache(directory: root, fetch: fetcher.fetch)
        let oldURL = URL(string: "https://example.invalid/old")!, newURL = URL(string: "https://example.invalid/new")!
        let original = await cache.imageData(accountID: account, key: member, sourceURL: oldURL, allowNetwork: true)
        await fetcher.setData(photo(.blue))
        let hint = await cache.imageData(accountID: account, key: member, sourceURL: newURL, allowNetwork: false)
        XCTAssertEqual(hint, original)
        let before = await fetcher.count
        XCTAssertEqual(before, 1)
        let refreshed = await cache.imageData(accountID: account, key: member, sourceURL: newURL, allowNetwork: true)
        XCTAssertNotEqual(refreshed, original)
        let after = await fetcher.count
        XCTAssertEqual(after, 2)
        let removed = await cache.imageData(accountID: account, key: member, sourceURL: nil, allowNetwork: true)
        let disk = await cache.cachedData(accountID: account, key: member)
        XCTAssertNil(removed)
        XCTAssertNil(disk)
    }

    func testExpiredPhotosAreUnavailableAndCanBeFetchedAgain() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = IdentityPhotoClock()
        let fetcher = IdentityPhotoFetcher(data: photo(.red))
        let cache = IdentityPhotoCache(directory: root, now: clock.read, fetch: fetcher.fetch)
        let account = UUID(), key = IdentityPhotoCache.Key.circle(UUID()), url = URL(string: "https://example.invalid/photo")!
        _ = await cache.imageData(accountID: account, key: key, sourceURL: url, allowNetwork: true)
        clock.advance(IdentityPhotoCache.lifetime)
        let expired = await cache.cachedData(accountID: account, key: key)
        XCTAssertNil(expired)
        let restored = await cache.imageData(accountID: account, key: key, sourceURL: url, allowNetwork: true)
        XCTAssertNotNil(restored)
        let count = await fetcher.count
        XCTAssertEqual(count, 2)
    }

    func testSignOutInvalidatesInFlightDownloadWithoutRecreatingFiles() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fetcher = IdentityPhotoFetcher(data: photo(.red), suspended: true)
        let cache = IdentityPhotoCache(directory: root, fetch: fetcher.fetch)
        let account = UUID(), key = IdentityPhotoCache.Key.member(UUID())
        let request = Task {
            await cache.imageData(accountID: account, key: key,
                sourceURL: URL(string: "https://example.invalid/photo")!, allowNetwork: true)
        }
        while await fetcher.count == 0 { await Task.yield() }
        await cache.clear(accountID: account)
        await fetcher.resume()
        let returned = await request.value
        let cached = await cache.cachedData(accountID: account, key: key)
        XCTAssertNil(returned)
        XCTAssertNil(cached)
        XCTAssertTrue(cacheFiles(root).isEmpty)
    }

    func testInvalidOrOversizedSourcesAreNeverPersistedAndNonHTTPSCannotFetch() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fetcher = IdentityPhotoFetcher(data: Data("not an image".utf8))
        let cache = IdentityPhotoCache(directory: root, fetch: fetcher.fetch)
        let account = UUID(), key = IdentityPhotoCache.Key.member(UUID())
        let insecure = await cache.imageData(accountID: account, key: key,
            sourceURL: URL(string: "http://example.invalid/photo")!, allowNetwork: true)
        XCTAssertNil(insecure)
        let initialCount = await fetcher.count
        XCTAssertEqual(initialCount, 0)
        let badImage = await cache.imageData(accountID: account, key: key,
            sourceURL: URL(string: "https://example.invalid/photo")!, allowNetwork: true)
        XCTAssertNil(badImage)
        await fetcher.setData(Data(repeating: 0, count: IdentityPhotoCache.maximumSourceBytes + 1))
        let large = await cache.imageData(accountID: account, key: key,
            sourceURL: URL(string: "https://example.invalid/large")!, allowNetwork: true)
        XCTAssertNil(large)
        XCTAssertTrue(cacheFiles(root).isEmpty)
    }

    func testDiskByteBudgetEvictsOlderEntries() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fetcher = IdentityPhotoFetcher(data: photo(.red))
        let account = UUID(), url = URL(string: "https://example.invalid/photo")!
        let measuring = IdentityPhotoCache(directory: root, fetch: fetcher.fetch)
        _ = await measuring.imageData(accountID: account, key: .member(UUID()), sourceURL: url, allowNetwork: true)
        let file = try XCTUnwrap(cacheFiles(root).first)
        let size = try XCTUnwrap(file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        await measuring.clear(accountID: account)
        let budget = size + 64
        let bounded = IdentityPhotoCache(directory: root, maximumAccountBytes: budget, fetch: fetcher.fetch)
        _ = await bounded.imageData(accountID: account, key: .member(UUID()), sourceURL: url, allowNetwork: true)
        _ = await bounded.imageData(accountID: account, key: .circle(UUID()), sourceURL: url, allowNetwork: true)
        let files = cacheFiles(root)
        let total = try files.reduce(0) { try $0 + XCTUnwrap($1.resourceValues(forKeys: [.fileSizeKey]).fileSize) }
        XCTAssertLessThanOrEqual(total, budget)
        XCTAssertEqual(files.count, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("IdentityPhotoTests-\(UUID())", isDirectory: true)
    }
    private func photo(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }
    private func cacheFiles(_ root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
    }
}

private actor IdentityPhotoFetcher {
    private var data: Data
    private let suspended: Bool
    private var continuation: CheckedContinuation<Data?, Never>?
    private(set) var count = 0
    init(data: Data, suspended: Bool = false) { self.data = data; self.suspended = suspended }
    func fetch(_ url: URL) async -> Data? {
        count += 1
        if suspended { return await withCheckedContinuation { continuation = $0 } }
        return data
    }
    func setData(_ data: Data) { self.data = data }
    func resume() { continuation?.resume(returning: data); continuation = nil }
}

private final class IdentityPhotoClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func read() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
