import SwiftUI
import XCTest
@testable import BlessingCircle

final class PhotoLayoutTests: XCTestCase {
    @MainActor
    func testPreviewUsesCachedOriginalAndKeepsOtherAccountsOnSmallPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = MediaDownloadCache(root: root.appendingPathComponent("cache"))
        let accountID = UUID()
        let originalURL = try XCTUnwrap(URL(string: "https://example.invalid/original.jpg"))
        func photo(_ size: CGSize, named name: String) throws -> URL {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let file = root.appendingPathComponent(name)
            try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: file)
            return file
        }
        let original = try photo(CGSize(width: 800, height: 1100), named: "download.jpg")
        let preview = try photo(CGSize(width: 480, height: 320), named: "old-preview.jpg")
        _ = try await cache.file(for: originalURL, accountID: accountID) { url in
            (original, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let repaired = await PhotoPreviewLoader.load(previewURL: preview, originalURL: originalURL, accountID: accountID, cache: cache)
        XCTAssertEqual(repaired?.size, CGSize(width: 800, height: 1100))
        let anotherAccount = UUID()
        let fallback = await PhotoPreviewLoader.load(previewURL: preview, originalURL: originalURL, accountID: anotherAccount, cache: cache)
        XCTAssertEqual(fallback?.size, CGSize(width: 480, height: 320))
        // With no preview and no cached original, show the open-photo placeholder.
        let missing = await PhotoPreviewLoader.load(previewURL: nil, originalURL: originalURL, accountID: anotherAccount, cache: cache)
        XCTAssertNil(missing)
        let local = await PhotoPreviewLoader.load(previewURL: preview, originalURL: preview, accountID: accountID, cache: cache)
        XCTAssertEqual(local?.size, CGSize(width: 480, height: 320))
    }

    @MainActor
    func testRenderedCardPhotosPreserveProportionsAtBothHeightCaps() throws {
        // Check rendered pixels as well as the sizing math: a resizable image can
        // still stretch inside a card even when its outer frame has the right size.
        for original in [CGSize(width: 800, height: 1100), CGSize(width: 1100, height: 800), CGSize(width: 800, height: 800)] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: original, format: format).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(origin: .zero, size: original))
            }
            for width: CGFloat in [280, 650] {
                for cap: CGFloat in [160, 520] {
                    let renderer = ImageRenderer(content:
                        Button {} label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AspectFitPhoto(image: image, maximumHeight: cap)
                                Text("Photo caption")
                            }
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .frame(width: width)
                        .background(.white)
                    )
                    renderer.scale = 1
                    let rendered = try XCTUnwrap(renderer.uiImage?.cgImage)
                    let pixelsWide = rendered.width
                    let pixelsHigh = rendered.height
                    var pixels = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)
                    let bounds = try pixels.withUnsafeMutableBytes { buffer -> CGRect in
                        let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                            width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8,
                            bytesPerRow: pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                        context.draw(rendered, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
                        let bytes = buffer.bindMemory(to: UInt8.self)
                        var minX = pixelsWide, minY = pixelsHigh, maxX = -1, maxY = -1
                        for y in 0..<pixelsHigh {
                            for x in 0..<pixelsWide {
                                let offset = (y * pixelsWide + x) * 4
                                if bytes[offset] > 220 && bytes[offset + 1] < 30 && bytes[offset + 2] < 30 {
                                    minX = min(minX, x); maxX = max(maxX, x)
                                    minY = min(minY, y); maxY = max(maxY, y)
                                }
                            }
                        }
                        guard maxX >= minX, maxY >= minY else { return .zero }
                        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                    }
                    XCTAssertGreaterThan(bounds.height, 0)
                    XCTAssertLessThanOrEqual(bounds.width, width - 20 + 1)
                    XCTAssertLessThanOrEqual(bounds.height, cap + 1)
                    XCTAssertEqual(bounds.width / bounds.height, original.width / original.height, accuracy: 0.02,
                        "Rendered photo \(original), card width \(width), height cap \(cap)")
                }
            }
        }
    }

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
