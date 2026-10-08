import ImageIO
import UIKit

/// The sender avatar fills the identity artwork. iOS adds its own app
/// icon badge at the lower right; that system badge cannot be replaced.
enum NotificationIdentityImage {
    static let size = CGSize(width: 256, height: 256)
    static func make(logo: UIImage?, avatar: UIImage?) -> UIImage? {
        guard let avatar, avatar.size.width > 0, avatar.size.height > 0 else { return logo }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = max(size.width / avatar.size.width, size.height / avatar.size.height)
            let drawnSize = CGSize(width: avatar.size.width * scale, height: avatar.size.height * scale)
            avatar.draw(in: CGRect(
                x: (size.width - drawnSize.width) / 2,
                y: (size.height - drawnSize.height) / 2,
                width: drawnSize.width,
                height: drawnSize.height
            ))
        }
    }

    static func loadAvatar(from url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
