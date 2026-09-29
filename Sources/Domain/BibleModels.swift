import Foundation

struct ScriptureReference: Codable, Hashable, Sendable {
    let bookSlug: String
    let bookName: String
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int

    var displayName: String {
        verseStart == verseEnd
            ? "\(bookName) \(chapter):\(verseStart)"
            : "\(bookName) \(chapter):\(verseStart)–\(verseEnd)"
    }
}

struct BibleTranslation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let shortName: String
    let name: String

    static let publicDomain: [BibleTranslation] = [
        .init(id: "web", shortName: "WEB", name: "World English Bible"),
        .init(id: "bsb", shortName: "BSB", name: "Berean Standard Bible"),
        .init(id: "kjv", shortName: "KJV", name: "King James Version"),
        .init(id: "asv", shortName: "ASV", name: "American Standard Version"),
        .init(id: "ylt", shortName: "YLT", name: "Young's Literal Translation"),
        .init(id: "dra", shortName: "DRA", name: "Douay-Rheims American Edition"),
        .init(id: "bbe", shortName: "BBE", name: "Bible in Basic English"),
        .init(id: "geneva1599", shortName: "GNV", name: "Geneva Bible 1599")
    ]
}

struct BibleBook: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let slug: String
    let chapterCount: Int

    static let all: [BibleBook] = [
        .init(id: 1, name: "Genesis", slug: "genesis", chapterCount: 50),
        .init(id: 2, name: "Exodus", slug: "exodus", chapterCount: 40),
        .init(id: 3, name: "Leviticus", slug: "leviticus", chapterCount: 27),
        .init(id: 4, name: "Numbers", slug: "numbers", chapterCount: 36),
        .init(id: 5, name: "Deuteronomy", slug: "deuteronomy", chapterCount: 34),
        .init(id: 6, name: "Joshua", slug: "joshua", chapterCount: 24),
        .init(id: 7, name: "Judges", slug: "judges", chapterCount: 21),
        .init(id: 8, name: "Ruth", slug: "ruth", chapterCount: 4),
        .init(id: 9, name: "1 Samuel", slug: "1-samuel", chapterCount: 31),
        .init(id: 10, name: "2 Samuel", slug: "2-samuel", chapterCount: 24),
        .init(id: 11, name: "1 Kings", slug: "1-kings", chapterCount: 22),
        .init(id: 12, name: "2 Kings", slug: "2-kings", chapterCount: 25),
        .init(id: 13, name: "1 Chronicles", slug: "1-chronicles", chapterCount: 29),
        .init(id: 14, name: "2 Chronicles", slug: "2-chronicles", chapterCount: 36),
        .init(id: 15, name: "Ezra", slug: "ezra", chapterCount: 10),
        .init(id: 16, name: "Nehemiah", slug: "nehemiah", chapterCount: 13),
        .init(id: 17, name: "Esther", slug: "esther", chapterCount: 10),
        .init(id: 18, name: "Job", slug: "job", chapterCount: 42),
        .init(id: 19, name: "Psalms", slug: "psalms", chapterCount: 150),
        .init(id: 20, name: "Proverbs", slug: "proverbs", chapterCount: 31),
        .init(id: 21, name: "Ecclesiastes", slug: "ecclesiastes", chapterCount: 12),
        .init(id: 22, name: "Song of Solomon", slug: "song-of-solomon", chapterCount: 8),
        .init(id: 23, name: "Isaiah", slug: "isaiah", chapterCount: 66),
        .init(id: 24, name: "Jeremiah", slug: "jeremiah", chapterCount: 52),
        .init(id: 25, name: "Lamentations", slug: "lamentations", chapterCount: 5),
        .init(id: 26, name: "Ezekiel", slug: "ezekiel", chapterCount: 48),
        .init(id: 27, name: "Daniel", slug: "daniel", chapterCount: 12),
        .init(id: 28, name: "Hosea", slug: "hosea", chapterCount: 14),
        .init(id: 29, name: "Joel", slug: "joel", chapterCount: 3),
        .init(id: 30, name: "Amos", slug: "amos", chapterCount: 9),
        .init(id: 31, name: "Obadiah", slug: "obadiah", chapterCount: 1),
        .init(id: 32, name: "Jonah", slug: "jonah", chapterCount: 4),
        .init(id: 33, name: "Micah", slug: "micah", chapterCount: 7),
        .init(id: 34, name: "Nahum", slug: "nahum", chapterCount: 3),
        .init(id: 35, name: "Habakkuk", slug: "habakkuk", chapterCount: 3),
        .init(id: 36, name: "Zephaniah", slug: "zephaniah", chapterCount: 3),
        .init(id: 37, name: "Haggai", slug: "haggai", chapterCount: 2),
        .init(id: 38, name: "Zechariah", slug: "zechariah", chapterCount: 14),
        .init(id: 39, name: "Malachi", slug: "malachi", chapterCount: 4),
        .init(id: 40, name: "Matthew", slug: "matthew", chapterCount: 28),
        .init(id: 41, name: "Mark", slug: "mark", chapterCount: 16),
        .init(id: 42, name: "Luke", slug: "luke", chapterCount: 24),
        .init(id: 43, name: "John", slug: "john", chapterCount: 21),
        .init(id: 44, name: "Acts", slug: "acts", chapterCount: 28),
        .init(id: 45, name: "Romans", slug: "romans", chapterCount: 16),
        .init(id: 46, name: "1 Corinthians", slug: "1-corinthians", chapterCount: 16),
        .init(id: 47, name: "2 Corinthians", slug: "2-corinthians", chapterCount: 13),
        .init(id: 48, name: "Galatians", slug: "galatians", chapterCount: 6),
        .init(id: 49, name: "Ephesians", slug: "ephesians", chapterCount: 6),
        .init(id: 50, name: "Philippians", slug: "philippians", chapterCount: 4),
        .init(id: 51, name: "Colossians", slug: "colossians", chapterCount: 4),
        .init(id: 52, name: "1 Thessalonians", slug: "1-thessalonians", chapterCount: 5),
        .init(id: 53, name: "2 Thessalonians", slug: "2-thessalonians", chapterCount: 3),
        .init(id: 54, name: "1 Timothy", slug: "1-timothy", chapterCount: 6),
        .init(id: 55, name: "2 Timothy", slug: "2-timothy", chapterCount: 4),
        .init(id: 56, name: "Titus", slug: "titus", chapterCount: 3),
        .init(id: 57, name: "Philemon", slug: "philemon", chapterCount: 1),
        .init(id: 58, name: "Hebrews", slug: "hebrews", chapterCount: 13),
        .init(id: 59, name: "James", slug: "james", chapterCount: 5),
        .init(id: 60, name: "1 Peter", slug: "1-peter", chapterCount: 5),
        .init(id: 61, name: "2 Peter", slug: "2-peter", chapterCount: 3),
        .init(id: 62, name: "1 John", slug: "1-john", chapterCount: 5),
        .init(id: 63, name: "2 John", slug: "2-john", chapterCount: 1),
        .init(id: 64, name: "3 John", slug: "3-john", chapterCount: 1),
        .init(id: 65, name: "Jude", slug: "jude", chapterCount: 1),
        .init(id: 66, name: "Revelation", slug: "revelation", chapterCount: 22)
    ]
}

struct BibleChapter: Hashable, Sendable {
    let verses: [String]
}

