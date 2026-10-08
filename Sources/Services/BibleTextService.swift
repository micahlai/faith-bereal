import Foundation

protocol BibleTextProviding: Sendable {
    func chapter(versionID: String, book: BibleBook, chapter: Int) async throws -> BibleChapter
    func passage(versionID: String, reference: ScriptureReference) async throws -> String
}

actor BibleAPIService: BibleTextProviding {
    private struct Envelope: Decodable {
        let data: PassageData
    }

    private struct PassageData: Decodable {
        let text: String
        let verses: [String]
    }

    private let baseURL = URL(string: "https://api.midvash.com/v1")!
    private var chapterCache: [String: BibleChapter] = [:]

    func chapter(versionID: String, book: BibleBook, chapter: Int) async throws -> BibleChapter {
        let key = "\(versionID)/\(book.slug)/\(chapter)"
        if let cached = chapterCache[key] { return cached }
        let decoded: Envelope = try await request(path: key)
        let result = BibleChapter(verses: decoded.data.verses)
        chapterCache[key] = result
        return result
    }

    func passage(versionID: String, reference: ScriptureReference) async throws -> String {
        let range = "\(reference.verseStart)-\(reference.verseEnd)"
        let decoded: Envelope = try await request(
            path: "\(versionID)/\(reference.bookSlug)/\(reference.chapter)/\(range)"
        )
        return BiblePassageFormatter.markedText(
            verses: decoded.data.verses,
            startingAt: reference.verseStart
        )
    }

    private func request<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
