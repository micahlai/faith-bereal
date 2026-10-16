import Foundation

/// Visible cards share a small metadata request; media and response bodies are never loaded here.
actor TimelineResponderSummaryCache {
    typealias Loader = @Sendable ([UUID]) async throws -> [TimelineResponderSummary]
    private struct Cached {
        let summary: TimelineResponseSummary
        let loadedAt: Date
    }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<TimelineResponseSummary, Error>
    }
    private var cached: [UUID: Cached] = [:]
    private var pending: [UUID: [Waiter]] = [:]
    private var scheduled = false
    private let capacity: Int
    private let lifetime: TimeInterval
    private let delay: Duration

    init(capacity: Int = 256, lifetime: TimeInterval = 60, delay: Duration = .milliseconds(35)) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
        self.delay = delay
    }

    func summary(for blessingID: UUID, now: Date = .now, load: @escaping Loader) async throws -> TimelineResponseSummary {
        try Task.checkCancellation()
        if let value = cached[blessingID], now.timeIntervalSince(value.loadedAt) < lifetime {
            return value.summary
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[blessingID, default: []].append(Waiter(id: waiterID, continuation: continuation))
                if !scheduled {
                    scheduled = true
                    Task { await self.drain(load: load) }
                }
            }
        } onCancel: {
            Task { await self.cancel(blessingID: blessingID, waiterID: waiterID) }
        }
    }

    private func cancel(blessingID: UUID, waiterID: UUID) {
        guard let index = pending[blessingID]?.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = pending[blessingID]!.remove(at: index)
        if pending[blessingID]?.isEmpty == true { pending.removeValue(forKey: blessingID) }
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func drain(load: @escaping Loader) async {
        try? await Task.sleep(for: delay)
        while !pending.isEmpty {
            // Keep in-flight waiters in pending so cancelled callers can leave independently.
            let ids = Array(pending.keys.sorted { $0.uuidString < $1.uuidString }.prefix(40))
            let requested = Set(ids)
            do {
                let summaries = try await load(ids)
                var authors: [UUID: Set<UUID>] = [:]
                var counts: [UUID: Int] = [:]
                var audioDates: [UUID: [Date]] = [:]
                for summary in summaries where requested.contains(summary.blessingID) {
                    authors[summary.blessingID, default: []].insert(summary.authorID)
                    counts[summary.blessingID, default: 0] += 1
                    if summary.mode == .voice, let date = summary.submittedAt {
                        audioDates[summary.blessingID, default: []].append(date)
                    }
                }
                for id in ids {
                    let value = TimelineResponseSummary(count: counts[id] ?? 0,
                        authorIDs: (authors[id] ?? []).sorted { $0.uuidString < $1.uuidString },
                        responseAudioDates: (audioDates[id] ?? []).sorted())
                    cached[id] = Cached(summary: value, loadedAt: .now)
                    let waiters = pending.removeValue(forKey: id) ?? []
                    for waiter in waiters { waiter.continuation.resume(returning: value) }
                }
                while cached.count > capacity, let oldest = cached.min(by: { $0.value.loadedAt < $1.value.loadedAt })?.key {
                    cached.removeValue(forKey: oldest)
                }
            } catch {
                for id in ids {
                    let waiters = pending.removeValue(forKey: id) ?? []
                    for waiter in waiters { waiter.continuation.resume(throwing: error) }
                }
            }
        }
        scheduled = false
    }
}

struct TimelineResponderSummary: Decodable, Equatable, Sendable {
    let blessingID: UUID
    let authorID: UUID
    let mode: ResponseMode?
    let submittedAt: Date?
    init(blessingID: UUID, authorID: UUID, mode: ResponseMode? = nil, submittedAt: Date? = nil) {
        self.blessingID = blessingID
        self.authorID = authorID
        self.mode = mode
        self.submittedAt = submittedAt
    }
    enum CodingKeys: String, CodingKey {
        case blessingID = "blessing_id"
        case authorID = "author_id"
        case mode
        case submittedAt = "submitted_at"
    }
}

struct TimelineResponseSummary: Equatable, Sendable {
    let count: Int
    let authorIDs: [UUID]
    let responseAudioDates: [Date]
    init(count: Int, authorIDs: [UUID], responseAudioDates: [Date] = []) {
        self.count = count
        self.authorIDs = authorIDs
        self.responseAudioDates = responseAudioDates
    }
    static let empty = TimelineResponseSummary(count: 0, authorIDs: [])
}

enum TimelineResponseSummaryError: Error { case unsupported }
