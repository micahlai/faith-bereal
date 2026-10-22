import Foundation
import CryptoKit

/// A disposable, account-scoped cache. Permanent saves live in SavedBlessingStore.
actor MediaDownloadCache {
    typealias Download = @Sendable (URL) async throws -> (URL, URLResponse)
    static let shared = MediaDownloadCache()
    static let maximumFileBytes = 128 * 1_024 * 1_024
    private let root: URL
    private let maximumBytes: Int
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date
    private var inFlight: [String: Task<URL, Error>] = [:]
    private var generations: [UUID: UUID] = [:]

    init(root: URL? = nil, maximumBytes: Int = 256 * 1_024 * 1_024,
         lifetime: TimeInterval = 7 * 86_400, now: @escaping @Sendable () -> Date = Date.init) {
        self.root = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadedMedia", isDirectory: true)
        self.maximumBytes = maximumBytes
        self.lifetime = lifetime
        self.now = now
    }

    static func identity(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        // Signed tokens authorize access, but do not identify different immutable bytes.
        parts.queryItems = parts.queryItems?.filter { !["token", "download"].contains($0.name.lowercased()) }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        parts.fragment = nil
        return parts.string ?? url.absoluteString
    }

    private func destination(_ url: URL, accountID: UUID) -> URL {
        let digest = SHA256.hash(data: Data(Self.identity(url).utf8)).map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.lowercased()
        return root.appendingPathComponent(accountID.uuidString, isDirectory: true)
            .appendingPathComponent(digest).appendingPathExtension(["caf", "m4a", "mp4", "mov", "jpg", "jpeg", "png", "heic"].contains(ext) ? ext : "data")
    }

    func cachedFile(for url: URL, accountID: UUID) -> URL? {
        let file = destination(url, accountID: accountID)
        guard let info = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]),
              let bytes = info.fileSize, bytes > 0,
              let created = info.creationDate, now().timeIntervalSince(created) >= 0,
              now().timeIntervalSince(created) < lifetime else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
        return file
    }

    func file(for url: URL, accountID: UUID, download: @escaping Download = MediaDownloadCache.download) async throws -> URL {
        if url.isFileURL { return url }
        guard url.scheme == "https", url.user == nil, url.password == nil else { throw URLError(.badURL) }
        if let cached = cachedFile(for: url, accountID: accountID) { return cached }
        let target = destination(url, accountID: accountID)
        let key = target.path
        if let work = inFlight[key] { return try await work.value }
        let generation = generations[accountID] ?? UUID()
        generations[accountID] = generation
        let work = Task { [download] in
            let (temporary, response) = try await download(url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MediaDownloadError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            try Task.checkCancellation()
            return try self.install(temporary, target: target, accountID: accountID, generation: generation)
        }
        inFlight[key] = work
        defer { inFlight[key] = nil }
        return try await work.value
    }

    private func install(_ source: URL, target: URL, accountID: UUID, generation: UUID) throws -> URL {
        guard generations[accountID] == generation else { throw CancellationError() }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= min(Self.maximumFileBytes, maximumBytes) else { throw URLError(.dataLengthExceedsMaximum) }
        var folder = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let staging = folder.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            .creationDate: now(), .modificationDate: now()], ofItemAtPath: staging.path)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staging, to: target)
        prune(keeping: target)
        return target
    }

    private func prune(keeping target: URL) {
        guard let files = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else { return }
        var entries: [(URL, Int, Date)] = []
        for case let file as URL in files {
            guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  info.isRegularFile == true else { continue }
            entries.append((file, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast))
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (file, bytes, _) in entries.sorted(by: { $0.2 < $1.2 }) where total > maximumBytes && file != target {
            try? FileManager.default.removeItem(at: file); total -= bytes
        }
    }

    func remove(for url: URL, accountID: UUID) {
        try? FileManager.default.removeItem(at: destination(url, accountID: accountID))
    }

    private static func download(_ url: URL) async throws -> (URL, URLResponse) {
        let span = BackendDiagnostics.shared.beginRequest(.storageOther)
        do {
            let (file, response) = try await URLSession.shared.download(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode
            let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            span.finish(httpStatus: status, receivedBytes: bytes.map(Int64.init))
            return (file, response)
        } catch { span.finish(error: error); throw error }
    }

    func clear(accountID: UUID) {
        generations[accountID] = UUID()
        let folder = root.appendingPathComponent(accountID.uuidString, isDirectory: true)
        for (key, work) in inFlight where key.hasPrefix(folder.path + "/") { work.cancel(); inFlight[key] = nil }
        try? FileManager.default.removeItem(at: folder)
    }
}

enum MediaDownloadError: Error { case httpStatus(Int) }
