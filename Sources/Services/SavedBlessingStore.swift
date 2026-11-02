import Foundation

struct SavedBlessingRecord: Codable, Sendable {
    let blessing: Blessing
    let responses: [BlessingResponse]
    let savedAt: Date
    // Only relative file names are persisted: app container paths can change.
    let files: [String: String]
    // Optional for compatibility with existing manual-save manifests.
    var automaticallySaved: Bool? = nil

    var isAutomatic: Bool { automaticallySaved == true }
    var hasAllSavedFiles: Bool {
        for key in files.keys {
            let url: URL?
            switch key {
            case "audio": url = blessing.audioURL
            case "video": url = blessing.videoURL
            case "photo": url = blessing.photoURL
            default: url = responses.first { $0.id.uuidString == key }?.audioURL
            }
            guard hasFile(url) else { return false }
        }
        return true
    }

    private func hasFile(_ url: URL?) -> Bool {
        guard let url, url.isFileURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 0
    }

    func containsRecording(for post: Blessing) -> Bool {
        switch post.captureMode {
        case .voice: hasFile(blessing.audioURL)
        case .video: hasFile(blessing.videoURL)
        case .typed: true
        }
    }

    func containsResponseAudio(_ id: UUID) -> Bool { hasFile(responses.first { $0.id == id }?.audioURL) }

    func coversPostMedia(_ post: Blessing, at now: Date = .now) -> Bool {
        if post.photoURL != nil && !hasFile(blessing.photoURL) { return false }
        if post.audioURL != nil || post.videoURL != nil || !MediaRetentionPolicy.isExpired(submittedAt: post.submittedAt, at: now) {
            if post.captureMode == .voice && !hasFile(blessing.audioURL) { return false }
            if post.captureMode == .video && !hasFile(blessing.videoURL) { return false }
        }
        return hasAllSavedFiles
    }

    func covers(blessing post: Blessing, responses visible: [BlessingResponse], at now: Date = .now) -> Bool {
        guard coversPostMedia(post, at: now) else { return false }
        for response in visible {
            guard let saved = responses.first(where: { $0.id == response.id }), saved.body == response.body else { return false }
            if response.mode == .voice,
               (response.audioURL != nil || !MediaRetentionPolicy.isExpired(submittedAt: response.submittedAt, at: now)),
               !hasFile(saved.audioURL) { return false }
        }
        return true
    }

    var containsExpiredMedia: Bool {
        expiredMedia(at: .now)
    }

    func expiredMedia(at now: Date) -> Bool {
        if (files["audio"] != nil || files["video"] != nil),
           MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt, at: now) { return true }
        return responses.contains {
            files[$0.id.uuidString] != nil && MediaRetentionPolicy.isExpired(submittedAt: $0.submittedAt, at: now)
        }
    }
}

protocol SavedBlessingMediaCopying: Sendable {
    func copy(from source: URL, to destination: URL) async throws
    func copy(from source: URL, to destination: URL, wifiOnly: Bool) async throws
}

extension SavedBlessingMediaCopying {
    func copy(from source: URL, to destination: URL, wifiOnly: Bool) async throws {
        try await copy(from: source, to: destination)
    }
}

struct SavedBlessingMediaCopier: SavedBlessingMediaCopying {
    func copy(from source: URL, to destination: URL) async throws {
        try await copy(from: source, to: destination, wifiOnly: false)
    }
    func copy(from source: URL, to destination: URL, wifiOnly: Bool) async throws {
        if source.isFileURL {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        guard source.scheme == "https" else { throw BlessingMediaSaveError.unavailable }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = !wifiOnly
        configuration.allowsExpensiveNetworkAccess = !wifiOnly
        configuration.allowsConstrainedNetworkAccess = !wifiOnly
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: source)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let bytes = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              bytes > 0 else { throw BlessingMediaSaveError.unavailable }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

actor SavedBlessingStore {
    private let root: URL
    private let copier: any SavedBlessingMediaCopying

    init(root: URL? = nil, copier: any SavedBlessingMediaCopying = SavedBlessingMediaCopier()) {
        var defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavedBlessings", isDirectory: true)
#if DEBUG
        if ProcessInfo.processInfo.environment["BLESSING_CIRCLE_FORCE_LOCAL"] == "1",
           let session = ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SAVING_TEST_SESSION"],
           let id = UUID(uuidString: session) {
            defaultRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SavingUITests-\(id.uuidString)")
        }
#endif
        self.root = root ?? defaultRoot
        self.copier = copier
    }

    func usage(userID: UUID) throws -> LocalArchiveUsage {
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: account.path) else { return LocalArchiveUsage(bytes: 0, blessingCount: 0) }
        var bytes: Int64 = 0
        let records = try load(userID: userID)
        for id in records.keys {
            let directory = account.appendingPathComponent(id.uuidString, isDirectory: true)
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            for case let file as URL in files {
                let value = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if value.isRegularFile == true { bytes += Int64(value.fileSize ?? 0) }
            }
        }
        return LocalArchiveUsage(bytes: bytes, blessingCount: records.count)
    }

    func load(userID: UUID) throws -> [UUID: SavedBlessingRecord] {
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: account.path) else { return [:] }
        var records: [UUID: SavedBlessingRecord] = [:]
        for directory in try FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  let record = loadRecord(blessingID: id, userID: userID) else { continue }
            records[id] = record
        }
        return records
    }

    func loadRecord(blessingID: UUID, userID: UUID) -> SavedBlessingRecord? {
        let directory = root.appendingPathComponent(userID.uuidString).appendingPathComponent(blessingID.uuidString)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("blessing.json")),
              let record = try? JSONDecoder().decode(SavedBlessingRecord.self, from: data),
              record.blessing.id == blessingID else { return nil }
        return resolved(record, in: directory)
    }

    func loadPreferences(userID: UUID) throws -> LocalSavingPreferences {
        let file = root.appendingPathComponent(userID.uuidString).appendingPathComponent("preferences.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return LocalSavingPreferences() }
        return try JSONDecoder().decode(LocalSavingPreferences.self, from: Data(contentsOf: file))
    }

    func savePreferences(_ preferences: LocalSavingPreferences, userID: UUID) throws {
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        try makeProtectedDirectory(account)
        try JSONEncoder().encode(preferences).write(to: account.appendingPathComponent("preferences.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func keepManually(blessingID: UUID, userID: UUID) throws -> SavedBlessingRecord? {
        guard var record = loadRecord(blessingID: blessingID, userID: userID) else { return nil }
        record.automaticallySaved = false
        let directory = root.appendingPathComponent(userID.uuidString).appendingPathComponent(blessingID.uuidString)
        try writeManifest(record, in: directory)
        return record
    }

    private var accountGenerations: [UUID: UUID] = [:]

    func save(blessing: Blessing, responses: [BlessingResponse], userID: UUID, now: Date = .now,
              automatically: Bool = false, refreshing: Bool = false, wifiOnly: Bool = false) async throws -> SavedBlessingRecord {
        let generation = accountGenerations[userID] ?? UUID()
        accountGenerations[userID] = generation
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        try makeProtectedDirectory(account)
        let destination = account.appendingPathComponent(blessing.id.uuidString, isDirectory: true)
        let existing = loadRecord(blessingID: blessing.id, userID: userID)
        if !MediaRetentionPolicy.isExpired(submittedAt: blessing.submittedAt, at: now) {
            if blessing.captureMode == .voice && blessing.audioURL == nil && existing?.blessing.audioURL == nil { throw BlessingMediaSaveError.unavailable }
            if blessing.captureMode == .video && blessing.videoURL == nil && existing?.blessing.videoURL == nil { throw BlessingMediaSaveError.unavailable }
        }
        for response in responses where response.mode == .voice && !MediaRetentionPolicy.isExpired(submittedAt: response.submittedAt, at: now) {
            if response.audioURL == nil && existing?.responses.first(where: { $0.id == response.id })?.audioURL == nil { throw BlessingMediaSaveError.unavailable }
        }
        if let existing, !refreshing, existing.covers(blessing: blessing, responses: responses, at: now) { return existing }
        let staging = account.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try makeProtectedDirectory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [String: String] = [:]
        var sources: [(String, URL)] = []
        if let url = blessing.audioURL ?? existing?.blessing.audioURL { sources.append(("audio", url)) }
        if let url = blessing.videoURL ?? existing?.blessing.videoURL { sources.append(("video", url)) }
        if let url = blessing.photoURL ?? existing?.blessing.photoURL { sources.append(("photo", url)) }
        for response in responses {
            if let url = response.audioURL ?? existing?.responses.first(where: { $0.id == response.id })?.audioURL {
                sources.append((response.id.uuidString, url))
            }
        }
        for (key, source) in sources {
            try Task.checkCancellation()
            let ext = source.pathExtension.lowercased()
            // Blessing media is immutable. A refreshed signed URL is not a new file.
            if let name = existing?.files[key],
               name == URL(fileURLWithPath: name).lastPathComponent,
               let size = try? destination.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                files[key] = name
                continue
            }
            let name = key + "-" + UUID().uuidString + "." + (["caf", "m4a", "mp4", "mov", "jpg", "jpeg", "png", "heic", "wav", "aac"].contains(ext) ? ext : "data")
            let target = staging.appendingPathComponent(name)
            let cached = source.isFileURL ? nil : await MediaDownloadCache.shared.cachedFile(for: source, accountID: userID)
            try await copier.copy(from: cached ?? source, to: target, wifiOnly: wifiOnly)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            files[key] = name
        }
        for name in files.values {
            let staged = staging.appendingPathComponent(name)
            let path = FileManager.default.fileExists(atPath: staged.path) ? staged : destination.appendingPathComponent(name)
            guard let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { throw BlessingMediaSaveError.unavailable }
        }
        try Task.checkCancellation()
        guard accountGenerations[userID] == generation else { throw CancellationError() }
        let record = SavedBlessingRecord(
            blessing: blessing.replacingMedia(audio: nil, video: nil, photo: nil),
            responses: responses.map { $0.replacingAudio(nil) }, savedAt: now, files: files,
            automaticallySaved: automatically
        )
        try writeManifest(record, in: staging)
        if let existing {
            // Install new files first, then atomically switch the manifest. A failed
            // refresh leaves the previous complete archive playable.
            var installed: [URL] = []
            do {
                for name in files.values where existing.files.values.contains(name) == false {
                    let target = destination.appendingPathComponent(name)
                    try FileManager.default.moveItem(at: staging.appendingPathComponent(name), to: target)
                    installed.append(target)
                }
                try writeManifest(record, in: destination)
            } catch {
                for file in installed { try? FileManager.default.removeItem(at: file) }
                throw error
            }
            for name in existing.files.values where files.values.contains(name) == false {
                guard name == URL(fileURLWithPath: name).lastPathComponent else { continue }
                try? FileManager.default.removeItem(at: destination.appendingPathComponent(name))
            }
            return resolved(record, in: destination)
        }
        // Publish only when every requested media file and the manifest exist.
        try FileManager.default.moveItem(at: staging, to: destination)
        return resolved(record, in: destination)
    }

    private func writeManifest(_ record: SavedBlessingRecord, in directory: URL) throws {
        let manifest = SavedBlessingRecord(
            blessing: record.blessing.replacingMedia(audio: nil, video: nil, photo: nil),
            responses: record.responses.map { $0.replacingAudio(nil) }, savedAt: record.savedAt,
            files: record.files, automaticallySaved: record.automaticallySaved
        )
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("blessing.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func removeContent(authorID: UUID, userID: UUID) throws {
        accountGenerations[userID] = UUID()
        for record in try load(userID: userID).values {
            if record.blessing.authorID == authorID {
                try unsave(blessingID: record.blessing.id, userID: userID)
                continue
            }
            let removed = record.responses.filter { $0.authorID == authorID }
            guard !removed.isEmpty else { continue }
            let directory = root.appendingPathComponent(userID.uuidString).appendingPathComponent(record.blessing.id.uuidString)
            var files = record.files
            for response in removed {
                if let name = files.removeValue(forKey: response.id.uuidString), name == URL(fileURLWithPath: name).lastPathComponent {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            let cleaned = SavedBlessingRecord(blessing: record.blessing, responses: record.responses.filter { $0.authorID != authorID }, savedAt: record.savedAt, files: files, automaticallySaved: record.automaticallySaved)
            try writeManifest(cleaned, in: directory)
        }
    }

    func removeAccount(userID: UUID) throws {
        accountGenerations[userID] = UUID()
        let directory = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func unsave(blessingID: UUID, userID: UUID) throws {
        let destination = root.appendingPathComponent(userID.uuidString, isDirectory: true)
            .appendingPathComponent(blessingID.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    private func makeProtectedDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ])
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    private func resolved(_ record: SavedBlessingRecord, in directory: URL) -> SavedBlessingRecord {
        func file(_ key: String) -> URL? {
            guard let name = record.files[key], name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
            let url = directory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return SavedBlessingRecord(
            blessing: record.blessing.replacingMedia(audio: file("audio"), video: file("video"), photo: file("photo")),
            responses: record.responses.map { $0.replacingAudio(file($0.id.uuidString)) },
            savedAt: record.savedAt, files: record.files, automaticallySaved: record.automaticallySaved
        )
    }
}
