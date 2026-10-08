import Foundation

struct SavedBlessingRecord: Codable, Sendable {
    let blessing: Blessing
    let responses: [BlessingResponse]
    let savedAt: Date
    // Only relative file names are persisted: app container paths can change.
    let files: [String: String]

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
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavedBlessings", isDirectory: true)
        self.copier = copier
    }

    func load(userID: UUID) throws -> [UUID: SavedBlessingRecord] {
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: account.path) else { return [:] }
        var records: [UUID: SavedBlessingRecord] = [:]
        for directory in try FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  let data = try? Data(contentsOf: directory.appendingPathComponent("blessing.json")),
                  let record = try? JSONDecoder().decode(SavedBlessingRecord.self, from: data),
                  record.blessing.id == id else { continue }
            records[id] = resolved(record, in: directory)
        }
        return records
    }

    func save(blessing: Blessing, responses: [BlessingResponse], userID: UUID, now: Date = .now) async throws -> SavedBlessingRecord {
        let account = root.appendingPathComponent(userID.uuidString, isDirectory: true)
        try makeProtectedDirectory(account)
        let destination = account.appendingPathComponent(blessing.id.uuidString, isDirectory: true)
        if let existing = try load(userID: userID)[blessing.id] { return existing }
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
            let name = key + "." + (["m4a", "mp4", "mov", "jpg", "jpeg", "png", "heic", "wav", "aac"].contains(ext) ? ext : "data")
            let target = staging.appendingPathComponent(name)
            try await copier.copy(from: source, to: target)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            files[key] = name
        }
        try Task.checkCancellation()
        let record = SavedBlessingRecord(
            blessing: blessing.replacingMedia(audio: nil, video: nil, photo: nil),
            responses: responses.map { $0.replacingAudio(nil) }, savedAt: now, files: files
        )
        try JSONEncoder().encode(record).write(to: staging.appendingPathComponent("blessing.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Publish only when every requested media file and the manifest exist.
        try FileManager.default.moveItem(at: staging, to: destination)
        return resolved(record, in: destination)
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
            savedAt: record.savedAt, files: record.files
        )
    }
}
