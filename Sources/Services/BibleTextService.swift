import Foundation

protocol BibleTextProviding: Sendable {
    func chapter(versionID: String, book: BibleBook, chapter: Int) async throws -> BibleChapter
    func passage(versionID: String, reference: ScriptureReference) async throws -> BiblePassage
}

enum BibleTextError: LocalizedError {
    case unsupportedVersion, invalidReference, unexpectedPassage

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This Bible version is no longer offered. Choose another in User settings."
        case .invalidReference: "This Bible reference could not be loaded."
        case .unexpectedPassage: "The Bible provider returned a different or incomplete passage. Please try again later."
        }
    }
}

actor BibleAPIService: BibleTextProviding {
    private struct Envelope: Decodable {
        let data: PassageData
        let meta: Metadata
    }

    private struct Metadata: Decodable {
        let copyright: String
    }

    private struct PassageData: Decodable {
        let version: String
        let book: String
        let chapter: Int
        let verse: Int
        let verseEnd: Int
        let verses: [String]
    }

    private let baseURL = URL(string: "https://api.midvash.com/v1")!
    private let session: URLSession
    private var chapterCache: [String: BibleChapter] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func chapter(versionID: String, book: BibleBook, chapter: Int) async throws -> BibleChapter {
        try validate(versionID: versionID, book: book, chapter: chapter)
        let key = "\(versionID)/\(book.slug)/\(chapter)"
        if let cached = chapterCache[key] { return cached }
        let decoded = try await request(path: key)
        try validate(decoded, versionID: versionID, book: book, chapter: chapter)
        guard decoded.data.verse == 1,
              decoded.data.verseEnd == decoded.data.verses.count else {
            throw BibleTextError.unexpectedPassage
        }
        let result = BibleChapter(verses: decoded.data.verses, credit: decoded.meta.copyright)
        chapterCache[key] = result
        return result
    }

    func passage(versionID: String, reference: ScriptureReference) async throws -> BiblePassage {
        guard let book = BibleBook.all.first(where: { $0.slug == reference.bookSlug }),
              reference.verseStart > 0, reference.verseEnd >= reference.verseStart,
              reference.verseEnd <= 176 else { throw BibleTextError.invalidReference }
        try validate(versionID: versionID, book: book, chapter: reference.chapter)
        let range = "\(reference.verseStart)-\(reference.verseEnd)"
        let decoded = try await request(path: "\(versionID)/\(book.slug)/\(reference.chapter)/\(range)")
        try validate(decoded, versionID: versionID, book: book, chapter: reference.chapter)
        guard decoded.data.verse == reference.verseStart,
              decoded.data.verseEnd == reference.verseEnd,
              decoded.data.verses.count == reference.verseEnd - reference.verseStart + 1 else {
            throw BibleTextError.unexpectedPassage
        }
        return BiblePassage(text: BiblePassageFormatter.markedText(
            verses: decoded.data.verses, startingAt: reference.verseStart), credit: decoded.meta.copyright)
    }

    private func validate(versionID: String, book: BibleBook, chapter: Int) throws {
        guard BibleTranslation.supports(versionID) else { throw BibleTextError.unsupportedVersion }
        guard BibleBook.all.contains(book), (1...book.chapterCount).contains(chapter) else {
            throw BibleTextError.invalidReference
        }
    }

    private func validate(_ decoded: Envelope, versionID: String, book: BibleBook, chapter: Int) throws {
        // The API aliases unavailable versions. Do not display or cache another
        // version under the requested translation's name.
        guard decoded.data.version == versionID, decoded.data.book == book.slug,
              decoded.data.chapter == chapter, !decoded.data.verses.isEmpty,
              decoded.data.verses.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              BibleTranslation.hasReviewedCredit(decoded.meta.copyright, versionID: versionID) else {
            throw BibleTextError.unexpectedPassage
        }
    }

    private func request(path: String) async throws -> Envelope {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Envelope.self, from: data)
    }
}
