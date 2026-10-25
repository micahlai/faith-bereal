import Foundation
import CryptoKit
import ImageIO

/// Display-only identity pictures. Account-scoped bytes never establish circle access.
actor IdentityPhotoCache {
    enum Key: Hashable, Sendable {
        case member(UUID)
        case circle(UUID)

        fileprivate var filename: String {
            switch self {
            case .member(let id): "member-\(id.uuidString.lowercased()).json"
            case .circle(let id): "circle-\(id.uuidString.lowercased()).json"
            }
        }
    }

    static let shared = IdentityPhotoCache()
    static let maximumSourceBytes = 10 * 1_024 * 1_024
    private struct Entry: Codable {
        let version: Int
        let accountID: UUID
        let sourceFingerprint: String
        let fetchedAt: Date
        let data: Data
    }
    private struct Request: Hashable {
        let accountID: UUID
        let key: Key
        let fingerprint: String
        let generation: UUID
    }
    private let directory: URL
    private let now: @Sendable () -> Date
    private let fetch: @Sendable (URL) async -> Data?
    private var generations: [UUID: UUID] = [:]
    private var inFlight: [Request: Task<Data?, Never>] = [:]

    init(directory: URL? = nil, legacyDirectory: URL? = nil,
         now: @escaping @Sendable () -> Date = Date.init,
         fetch: @escaping @Sendable (URL) async -> Data? = IdentityPhotoCache.download) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IdentityPhotos", isDirectory: true)
        // Carry existing photos out of the system-purgeable cache on upgrade.
        let legacy = legacyDirectory ?? (directory == nil
            ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("IdentityPhotos", isDirectory: true) : nil)
        if let legacy, !FileManager.default.fileExists(atPath: self.directory.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.createDirectory(at: self.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: legacy, to: self.directory)
        }
        self.now = now
        self.fetch = fetch
    }

    /// Read before attempting a refresh so a changing signed URL does not flash initials.
    func cachedData(accountID: UUID, key: Key) -> Data? {
        read(accountID: accountID, key: key)?.data
    }

    func imageData(accountID: UUID, key: Key, sourceURL: URL?, allowNetwork: Bool) async -> Data? {
        guard !Task.isCancelled else { return nil }
        guard let sourceURL else {
            if allowNetwork { remove(accountID: accountID, key: key); return nil }
            return read(accountID: accountID, key: key)?.data
        }
        let cached = read(accountID: accountID, key: key)
        guard allowNetwork else { return cached?.data }
        guard sourceURL.scheme?.lowercased() == "https", sourceURL.host != nil,
              sourceURL.user == nil, sourceURL.password == nil else { return nil }
        let fingerprint = Self.fingerprint(sourceURL)
        if cached?.sourceFingerprint == fingerprint { return cached?.data }
        let generation = generations[accountID] ?? UUID()
        generations[accountID] = generation
        let request = Request(accountID: accountID, key: key, fingerprint: fingerprint, generation: generation)
        let work: Task<Data?, Never>
        if let existing = inFlight[request] {
            work = existing
        } else {
            let fetch = self.fetch
            work = Task { await fetch(sourceURL) }
            inFlight[request] = work
        }
        let downloaded = await work.value
        inFlight[request] = nil
        guard generations[accountID] == generation, !Task.isCancelled else { return nil }
        guard let downloaded, downloaded.count <= Self.maximumSourceBytes,
              let imageData = Self.normalizedImage(downloaded) else { return cached?.data }
        let entry = Entry(version: 1, accountID: accountID, sourceFingerprint: fingerprint,
                          fetchedAt: now(), data: imageData)
        save(entry, key: key)
        return imageData
    }

    /// Save every known identity, even if its avatar never scrolls into view.
    /// The caller supplies fresh membership metadata; this never establishes access.
    func synchronize(accountID: UUID, currentUser: Member, circles: [CircleGroup]) async {
        guard currentUser.id == accountID else { return }
        var members = Dictionary(circles.flatMap(\.members).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        members[currentUser.id] = currentUser
        var sources = members.values.map { (Key.member($0.id), $0.avatarURL) }
        sources += circles.map { (Key.circle($0.id), $0.photoURL) }
        for (key, url) in sources {
            guard !Task.isCancelled else { return }
            _ = await imageData(accountID: accountID, key: key, sourceURL: url, allowNetwork: true)
        }
    }

    /// Invalidates delayed downloads before removing the signed-out account's files.
    func clear(accountID: UUID) {
        generations[accountID] = UUID()
        for (request, task) in inFlight where request.accountID == accountID {
            task.cancel()
            inFlight[request] = nil
        }
        try? FileManager.default.removeItem(at: accountDirectory(accountID))
    }

    private func read(accountID: UUID, key: Key) -> Entry? {
        let file = fileURL(accountID: accountID, key: key)
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 2 * Self.maximumSourceBytes else {
                remove(accountID: accountID, key: key)
                return nil
            }
            let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
            guard entry.version == 1, entry.accountID == accountID,
                  entry.data.count <= Self.maximumSourceBytes else {
                remove(accountID: accountID, key: key)
                return nil
            }
            return entry
        } catch {
            remove(accountID: accountID, key: key)
            return nil
        }
    }

    private func save(_ entry: Entry, key: Key) {
        do {
            let data = try JSONEncoder().encode(entry)
            try protectDirectory(directory)
            try protectDirectory(accountDirectory(entry.accountID))
            var file = fileURL(accountID: entry.accountID, key: key)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        } catch {
            remove(accountID: entry.accountID, key: key)
        }
    }

    private func protectDirectory(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    private func remove(accountID: UUID, key: Key) {
        try? FileManager.default.removeItem(at: fileURL(accountID: accountID, key: key))
    }
    private func accountDirectory(_ accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString.lowercased(), isDirectory: true)
    }
    private func fileURL(accountID: UUID, key: Key) -> URL {
        accountDirectory(accountID).appendingPathComponent(key.filename)
    }
    private static func fingerprint(_ url: URL) -> String {
        SHA256.hash(data: Data(MediaDownloadCache.identity(url).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Bound decoded image size as well as transport bytes. Preserve transparent avatars.
    private static func normalizedImage(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func download(_ url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: IdentityPhotoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpShouldHandleCookies = false
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  response.expectedContentLength <= maximumSourceBytes else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumSourceBytes, !Task.isCancelled else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil }
    }
}

private final class IdentityPhotoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        completionHandler(url?.scheme?.lowercased() == "https" && url?.user == nil && url?.password == nil ? request : nil)
    }
}
