import XCTest
@testable import BlessingCircle

final class BlessingTextPolicyTests: XCTestCase {
    func testLengthBoundariesAndTrimmedEmptyInput() throws {
        for length in [1, 600, 601, 1_199, 1_200] {
            let body = String(repeating: "a", count: length)
            XCTAssertEqual(try BlessingTextPolicy.validated(" \(body)\n"), body)
        }
        XCTAssertThrowsError(try BlessingTextPolicy.validated(String(repeating: "a", count: 1_201))) {
            XCTAssertEqual($0 as? BlessingError, .blessingTooLong)
        }
        for body in [nil, "", " \n "] as [String?] {
            XCTAssertThrowsError(try BlessingTextPolicy.validated(body)) {
                XCTAssertEqual($0 as? BlessingError, .emptyBlessing)
            }
        }
    }

    func testUnicodeLengthMatchesDatabaseWithoutSplittingCombinedCharacters() throws {
        let emoji = "👨‍👩‍👧‍👦"
        XCTAssertEqual(BlessingTextPolicy.length(of: emoji), 7)
        let valid = String(repeating: emoji, count: 171)
        XCTAssertEqual(try BlessingTextPolicy.validated(valid), valid)
        let over = String(repeating: emoji, count: 172)
        XCTAssertThrowsError(try BlessingTextPolicy.validated(over))
        XCTAssertEqual(BlessingTextPolicy.limited(over), valid)
        let prefix = String(repeating: "a", count: 1_199)
        XCTAssertEqual(BlessingTextPolicy.limited(prefix + "e\u{301}"), prefix)
    }

    func testAllCaptureModesAndEditsAccept1200AndReject1201() async throws {
        let now = Date()
        let valid = String(repeating: "a", count: 1_200)
        let over = valid + "a"
        for mode in CaptureMode.allCases {
            let repository = LocalBlessingRepository(now: now)
            let bootstrap = try await repository.bootstrap()
            let prompt = try XCTUnwrap(bootstrap.prompt)
            let media = URL(fileURLWithPath: "/tmp/character-limit-fixture")
            do {
                _ = try await repository.submit(
                    promptID: prompt.id, authorID: bootstrap.currentUser.id, mode: mode,
                    body: over, audioURL: mode == .voice ? media : nil,
                    videoURL: mode == .video ? media : nil, scriptureReference: nil, now: now)
                XCTFail("Oversized \(mode) blessing accepted")
            } catch let error as BlessingError {
                XCTAssertEqual(error, .blessingTooLong)
            }
            let blessing = try await repository.submit(
                promptID: prompt.id, authorID: bootstrap.currentUser.id, mode: mode,
                body: valid, audioURL: mode == .voice ? media : nil,
                videoURL: mode == .video ? media : nil, scriptureReference: nil, now: now)
            XCTAssertEqual(blessing.body, valid)
            let edited = try await repository.updateBlessing(
                blessingID: blessing.id, authorID: bootstrap.currentUser.id,
                body: " \(valid) ", scriptureReference: nil, now: now.addingTimeInterval(1))
            XCTAssertEqual(edited.body, valid)
            do {
                _ = try await repository.updateBlessing(
                    blessingID: blessing.id, authorID: bootstrap.currentUser.id,
                    body: over, scriptureReference: nil, now: now.addingTimeInterval(2))
                XCTFail("Oversized edit accepted")
            } catch let error as BlessingError {
                XCTAssertEqual(error, .blessingTooLong)
            }
        }
    }
}
