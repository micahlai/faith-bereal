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
}

struct SavedBlessingMediaCopier: SavedBlessingMediaCopying {
    func copy(from source: URL, to destination: URL) async throws {
        if source.isFileURL {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        guard source.scheme == "https" else { throw BlessingMediaSaveError.unavailable }
        let (temporary, response) = try await URLSession.shared.download(from: source)
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

    private func loadRecord(blessingID: UUID, userID: UUID) -> SavedBlessingRecord? {
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

    func save(blessing: Blessing, responses: [BlessingResponse], userID: UUID, now: Date = .now,
              automatically: Bool = false, refreshing: Bool = false) async throws -> SavedBlessingRecord {
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        try makeProtectedDirectory(account)
        let destination = account.appendingPathComponent(blessing.id.uuidString, isDirectory: true)
        let existing = loadRecord(blessingID: blessing.id, userID: userID)
        if let existing, !refreshing { return existing }
        let staging = account.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try makeProtectedDirectory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [String: String] = [:]
        var sources: [(String, URL)] = []
        if let url = blessing.audioURL { sources.append(("audio", url)) }
        if let url = blessing.videoURL { sources.append(("video", url)) }
        if let url = blessing.photoURL { sources.append(("photo", url)) }
        for response in responses {
            if let url = response.audioURL { sources.append((response.id.uuidString, url)) }
        }
        for (key, source) in sources {
            try Task.checkCancellation()
            let ext = source.pathExtension.lowercased()
            if let name = existing?.files[key], source == destination.appendingPathComponent(name),
               FileManager.default.fileExists(atPath: source.path) {
                files[key] = name
                continue
            }
            let name = key + "-" + UUID().uuidString + "." + (["m4a", "mp4", "mov", "jpg", "jpeg", "png", "heic", "wav", "aac"].contains(ext) ? ext : "data")
            let target = staging.appendingPathComponent(name)
            try await copier.copy(from: source, to: target)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            files[key] = name
        }
        try Task.checkCancellation()
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
