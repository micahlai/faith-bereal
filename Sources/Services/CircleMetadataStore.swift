import Foundation

/// Display hints only. A snapshot never proves membership, ownership, permission,
/// prompt eligibility, or permission to read blessing content.
struct CircleMetadataSnapshot: Codable, Sendable {
    let currentUser: Member
    let circles: [CircleGroup]
    let selectedCircleID: UUID?
    let updatedAt: Date
}

/// Protected, account-scoped metadata for the initial loading presentation.
/// No prompts, blessings, responses, or invitation codes enter this store.
actor CircleMetadataStore {
    static let shared = CircleMetadataStore()

    private struct Envelope: Codable {
        let version: Int
        let accountID: UUID
        let snapshot: CircleMetadataSnapshot
    }

    private let directory: URL
    private let now: @Sendable () -> Date
    private let maximumBytes = 8 * 1_024 * 1_024

    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CircleMetadata", isDirectory: true)
        self.now = now
    }

    func load(accountID: UUID) -> CircleMetadataSnapshot? {
        let url = fileURL(accountID: accountID)
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= maximumBytes else {
                remove(accountID: accountID)
                return nil
            }
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
            guard envelope.version == 1, envelope.accountID == accountID,
                  envelope.snapshot.currentUser.id == accountID else {
                remove(accountID: accountID)
                return nil
            }
            // Sanitize on read too, including data written by an older client.
            return sanitized(accountID: accountID, currentUser: envelope.snapshot.currentUser,
                             circles: envelope.snapshot.circles, selectedCircleID: envelope.snapshot.selectedCircleID,
                             updatedAt: envelope.snapshot.updatedAt)
        } catch {
            // Missing/unreadable/corrupt cache is harmless; the live fetch remains authoritative.
            remove(accountID: accountID)
            return nil
        }
    }

    func save(accountID: UUID, currentUser: Member, circles: [CircleGroup], selectedCircleID: UUID?) {
        guard !Task.isCancelled else { return }
        guard let snapshot = sanitized(accountID: accountID, currentUser: currentUser, circles: circles,
                                       selectedCircleID: selectedCircleID, updatedAt: now()) else {
            remove(accountID: accountID)
            return
        }
        do {
            let data = try JSONEncoder().encode(Envelope(version: 1, accountID: accountID, snapshot: snapshot))
            guard data.count <= maximumBytes else {
                remove(accountID: accountID)
                return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            var url = fileURL(accountID: accountID)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try url.setResourceValues(values)
        } catch {
            // A display optimization must not block a successful server operation.
            remove(accountID: accountID)
        }
    }

    func remove(accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(accountID: accountID))
    }

    private func fileURL(accountID: UUID) -> URL {
        directory.appendingPathComponent(accountID.uuidString.lowercased()).appendingPathExtension("json")
    }

    private func sanitized(accountID: UUID, currentUser: Member, circles: [CircleGroup],
                           selectedCircleID: UUID?, updatedAt: Date) -> CircleMetadataSnapshot? {
        guard currentUser.id == accountID else { return nil }
        var seen: Set<UUID> = []
        let displayCircles = circles.compactMap { circle -> CircleGroup? in
            guard seen.insert(circle.id).inserted,
                  circle.members.contains(where: { $0.id == accountID }),
                  Set(circle.members.map(\.id)).count == circle.members.count else { return nil }
            var display = circle
            display.inviteCode = ""
            display.allowMemberCircleChanges = false
            if let streaks = display.streaks {
                let memberIDs = Set(display.members.map(\.id))
                display.streaks = streaks.filter { key, value in memberIDs.contains(key) && key == value.memberID }
            }
            return display
        }
        let selection = selectedCircleID.flatMap { selected in displayCircles.contains { $0.id == selected } ? selected : nil }
        return CircleMetadataSnapshot(currentUser: currentUser, circles: displayCircles,
                                      selectedCircleID: selection, updatedAt: updatedAt)
    }
}
