import Foundation

struct LocalSavingPreferences: Codable, Sendable {
    var isEnabled = false
    var hasChosen = false
    var excludedBlessingIDs: Set<UUID> = []
}

enum AutomaticSaveKeepChoice: String, CaseIterable, Identifiable {
    case all, mine, none, selected

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Keep all"
        case .mine: "Keep only my blessings"
        case .none: "Keep none"
        case .selected: "Choose from a list"
        }
    }

    func keptIDs(records: [SavedBlessingRecord], userID: UUID, selectedIDs: Set<UUID>) -> Set<UUID> {
        Set(records.filter {
            switch self {
            case .all: true
            case .mine: $0.blessing.authorID == userID
            case .none: false
            case .selected: selectedIDs.contains($0.blessing.id)
            }
        }.map(\.blessing.id))
    }
}
