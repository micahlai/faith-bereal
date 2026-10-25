import SwiftUI
import XCTest
@testable import BlessingCircle

final class PhotoLayoutTests: XCTestCase {
    func testPortraitAndLandscapePhotosKeepTheirRatiosWithinHeightAndWidthCaps() {
        for original in [CGSize(width: 1200, height: 2400), CGSize(width: 2400, height: 1200), CGSize(width: 900, height: 900)] {
            for width: CGFloat in [280, 650] {
                for height: CGFloat in [160, 520] {
                    let size = PhotoAspectLayout(imageSize: original, maximumHeight: height).fittedSize(proposedWidth: width)
                    XCTAssertGreaterThan(size.width, 0)
                    XCTAssertLessThanOrEqual(size.width, width)
                    XCTAssertLessThanOrEqual(size.height, height)
                    XCTAssertEqual(size.width / size.height, original.width / original.height, accuracy: 0.0001)
                }
            }
        }
    }

    func testInvalidAndUnconstrainedPhotoProposalsAreFinite() {
        let layout = PhotoAspectLayout(imageSize: CGSize(width: 400, height: 800), maximumHeight: 520)
        XCTAssertEqual(layout.fittedSize(proposedWidth: nil), CGSize(width: 260, height: 520))
        XCTAssertEqual(layout.fittedSize(proposedWidth: .infinity), CGSize(width: 260, height: 520))
        XCTAssertEqual(layout.fittedSize(proposedWidth: 0), .zero)
        XCTAssertEqual(PhotoAspectLayout(imageSize: .zero, maximumHeight: 520).fittedSize(proposedWidth: 300), .zero)
    }
}
