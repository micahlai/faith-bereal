import XCTest
@testable import BlessingCircle

final class BlessingMediaSaverTests: XCTestCase {
    func testDeniedAccessDoesNotDownloadOrSave() async {
        let downloader = RecordingMediaDownloader()
        let library = RecordingPhotoLibrary(allowsAccess: false)
        let saver = BlessingMediaSaver(downloader: downloader, library: library)
        do {
            try await saver.save(url: URL(string: "https://example.com/photo.jpg")!, kind: .photo)
            XCTFail("Denied Photos access must fail")
        } catch {
            XCTAssertEqual(error as? BlessingMediaSaveError, .permissionDenied)
        }
        let downloadCount = await downloader.callCount
        let saves = await library.savedKinds
        XCTAssertEqual(downloadCount, 0)
        XCTAssertTrue(saves.isEmpty)
    }

    func testPhotosAndVideosReachLibraryWithoutDeletingLocalOriginals() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let downloader = RecordingMediaDownloader(file: .init(url: url, isTemporary: false))
        let library = RecordingPhotoLibrary(allowsAccess: true)
        let saver = BlessingMediaSaver(downloader: downloader, library: library)
        try await saver.save(url: URL(string: "https://example.com/peer-photo.jpg")!, kind: .photo)
        try await saver.save(url: URL(string: "https://example.com/own-video.mp4")!, kind: .video)
        let saves = await library.savedKinds
        XCTAssertEqual(saves, [.photo, .video])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDownloadedTemporaryFileIsRemovedAfterSuccessfulSave() async throws {
        try await assertTemporaryFileRemoved(failsSave: false)
    }

    func testDownloadedTemporaryFileIsRemovedAfterFailedSave() async throws {
        try await assertTemporaryFileRemoved(failsSave: true)
    }

    func testLocalDownloaderPreservesOriginalFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try await URLSessionBlessingMediaDownloader().localFile(for: url, kind: .photo)
        XCTAssertEqual(file.url, url)
        XCTAssertFalse(file.isTemporary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDownloaderRejectsInsecureURLAndMissingLocalMedia() async {
        for url in [URL(string: "http://example.com/photo.jpg")!,
                    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)] {
            do {
                _ = try await URLSessionBlessingMediaDownloader().localFile(for: url, kind: .photo)
                XCTFail("Unavailable media must fail")
            } catch {
                XCTAssertEqual(error as? BlessingMediaSaveError, .unavailable)
            }
        }
    }

    private func assertTemporaryFileRemoved(failsSave: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let saver = BlessingMediaSaver(
            downloader: RecordingMediaDownloader(file: BlessingDownloadedMedia(url: url, isTemporary: true)),
            library: RecordingPhotoLibrary(allowsAccess: true, failsSave: failsSave)
        )
        do {
            try await saver.save(url: URL(string: "https://example.com/photo.jpg")!, kind: .photo)
            XCTAssertFalse(failsSave)
        } catch {
            XCTAssertTrue(failsSave)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

private actor RecordingMediaDownloader: BlessingMediaDownloading {
    var callCount = 0
    let file: BlessingDownloadedMedia

    init(file: BlessingDownloadedMedia = .init(url: URL(fileURLWithPath: "/test/photo.jpg"), isTemporary: false)) {
        self.file = file
    }

    func localFile(for url: URL, kind: BlessingSavedMediaKind) async throws -> BlessingDownloadedMedia {
        callCount += 1
        return file
    }
}

private actor RecordingPhotoLibrary: BlessingMediaPhotoLibrary {
    let allowsAccess: Bool
    let failsSave: Bool
    var savedKinds: [BlessingSavedMediaKind] = []

    init(allowsAccess: Bool, failsSave: Bool = false) {
        self.allowsAccess = allowsAccess
        self.failsSave = failsSave
    }

    func requestAddAccess() async -> Bool { allowsAccess }

    func save(fileURL: URL, kind: BlessingSavedMediaKind) async throws {
        if failsSave { throw BlessingMediaSaveError.unavailable }
        savedKinds.append(kind)
    }
}
