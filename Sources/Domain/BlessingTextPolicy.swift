import Foundation

enum BlessingTextPolicy {
    static let maximumLength = 1_200

    // PostgreSQL char_length counts Unicode scalars, not Swift grapheme clusters.
    static func length(of text: String) -> Int { text.unicodeScalars.count }

    static func validated(_ text: String?) throws -> String {
        let cleaned = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw BlessingError.emptyBlessing }
        guard length(of: cleaned) <= maximumLength else { throw BlessingError.blessingTooLong }
        return cleaned
    }

    static func limited(_ text: String) -> String {
        guard length(of: text) > maximumLength else { return text }
        var count = 0
        return String(text.prefix { character in
            count += character.unicodeScalars.count
            return count <= maximumLength
        })
    }
}
