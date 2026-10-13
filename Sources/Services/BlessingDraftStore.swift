import Foundation

actor BlessingDraftStore {
    private struct Manifest: Codable {
        var draft: BlessingDraft
        var sourceFiles: [String: String]
    }
    private let root: URL
    private var completed: Set<String> = []
    init(root: URL? = nil) {
        var resolved = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlessingDrafts", isDirectory: true)
#if DEBUG
        if root == nil, ProcessInfo.processInfo.environment["BLESSING_CIRCLE_FORCE_LOCAL"] == "1",
           let raw = ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SAVING_TEST_SESSION"], let session = UUID(uuidString: raw) {
            resolved = resolved.appendingPathComponent("Tests-\(session.uuidString)", isDirectory: true)
        }
#endif
        self.root = resolved
    }

    func save(_ draft: BlessingDraft, now: Date = .now) throws -> BlessingDraft? {
        guard !completed.contains(key(draft.authorID, draft.circleID, draft.promptID)) else { return nil }
        guard now < draft.expiresAt else {
            try remove(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
            return nil
        }
        guard draft.hasContent else {
            try remove(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
            return nil
        }
        let folder = directory(authorID: draft.authorID, circleID: draft.circleID, promptID: draft.promptID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = folder
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try excluded.setResourceValues(attributes)
        let stateURL = folder.appendingPathComponent("draft.json")
        let old = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: stateURL))
        if let old, old.draft.updatedAt > draft.updatedAt { return old.draft }
        var files: [String: String] = [:]
        var created: [URL] = []
        var committed = false
        defer { if !committed { created.forEach { try? FileManager.default.removeItem(at: $0) } } }

        func copy(_ source: URL?) throws -> URL? {
            guard let source else { return nil }
            guard source.isFileURL else { throw BlessingMediaSaveError.unavailable }
            let info = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard (info.fileSize ?? 0) > 0 else { throw BlessingMediaSaveError.unavailable }
            let fingerprint = "\(source.path)|\(info.fileSize ?? 0)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            if let name = files[fingerprint] { return folder.appendingPathComponent(name) }
            if source.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                files[fingerprint] = source.lastPathComponent
                return source
            }
            if let name = old?.sourceFiles[fingerprint], FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                files[fingerprint] = name
                return folder.appendingPathComponent(name)
            }
            let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            try FileManager.default.copyItem(at: source, to: destination)
            created.append(destination)
            files[fingerprint] = destination.lastPathComponent
            return destination
        }
        var saved = draft
        saved.audioSegments = try draft.audioSegments.compactMap { try copy($0) }
        saved.videoURL = try copy(draft.videoURL)
        saved.photoURL = try copy(draft.photoURL)
        let data = try JSONEncoder().encode(Manifest(draft: saved, sourceFiles: files))
        try data.write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        committed = true
        // Only obsolete copies inside this particular draft folder are removed.
        let retained = Set(files.values)
        for name in Set(old?.sourceFiles.values.map { $0 } ?? []) where !retained.contains(name) {
            guard name == URL(fileURLWithPath: name).lastPathComponent else { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        return saved
    }

    func load(authorID: UUID, now: Date = .now) throws -> [BlessingDraft] {
        let account = root.appendingPathComponent(authorID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: account.path) else { return [] }
        var drafts: [BlessingDraft] = []
        for circle in try FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) {
            guard let circleID = UUID(uuidString: circle.lastPathComponent) else { continue }
            for folder in try FileManager.default.contentsOfDirectory(at: circle, includingPropertiesForKeys: nil) {
                guard let promptID = UUID(uuidString: folder.lastPathComponent),
                      let data = try? Data(contentsOf: folder.appendingPathComponent("draft.json")),
                      let record = try? JSONDecoder().decode(Manifest.self, from: data),
                      record.draft.authorID == authorID, record.draft.circleID == circleID,
                      record.draft.promptID == promptID else { continue }
                guard now < record.draft.expiresAt else {
                    try remove(authorID: authorID, circleID: circleID, promptID: promptID)
                    continue
                }
                var draft = record.draft
                func restored(_ url: URL?) -> URL? { url.map { folder.appendingPathComponent($0.lastPathComponent) } }
                draft.audioSegments = draft.audioSegments.compactMap { restored($0) }
                draft.photoURL = restored(draft.photoURL)
                draft.videoURL = restored(draft.videoURL)
                drafts.append(draft)
            }
        }
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    func remove(authorID: UUID, circleID: UUID, promptID: UUID) throws {
        let folder = directory(authorID: authorID, circleID: circleID, promptID: promptID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    func beginEditing(authorID: UUID, circleID: UUID, promptID: UUID) {
        completed.remove(key(authorID, circleID, promptID))
    }

    func copyForEditing(_ draft: BlessingDraft) throws -> BlessingDraft {
        var editable = draft
        editable.audioSegments = try draft.audioSegments.map { try CaptureMediaStore.persistDraftMedia(from: $0) }
        editable.photoURL = try draft.photoURL.map { try CaptureMediaStore.persistDraftMedia(from: $0) }
        editable.videoURL = try draft.videoURL.map { try CaptureMediaStore.persistDraftMedia(from: $0) }
        return editable
    }

    func markSent(authorID: UUID, circleID: UUID, promptID: UUID) throws {
        completed.insert(key(authorID, circleID, promptID))
        try remove(authorID: authorID, circleID: circleID, promptID: promptID)
    }

    private func key(_ authorID: UUID, _ circleID: UUID, _ promptID: UUID) -> String {
        "\(authorID)-\(circleID)-\(promptID)"
    }

    private func directory(authorID: UUID, circleID: UUID, promptID: UUID) -> URL {
        root.appendingPathComponent(authorID.uuidString, isDirectory: true)
            .appendingPathComponent(circleID.uuidString, isDirectory: true)
            .appendingPathComponent(promptID.uuidString, isDirectory: true)
    }
}
