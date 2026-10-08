import ImageIO
import UIKit

/// The sender avatar lives inside the identity artwork. iOS adds its own app
/// icon badge at the lower right; that system badge cannot be replaced.
enum NotificationIdentityImage {
    static let size = CGSize(width: 256, height: 256)
    static let avatarFrame = CGRect(x: 32, y: 142, width: 82, height: 82)

    static func make(logo: UIImage, avatar: UIImage?) -> UIImage {
        guard let avatar, avatar.size.width > 0, avatar.size.height > 0 else { return logo }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            logo.draw(in: CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            context.saveGState()
            UIBezierPath(ovalIn: avatarFrame).addClip()
            let scale = max(avatarFrame.width / avatar.size.width, avatarFrame.height / avatar.size.height)
            let drawnSize = CGSize(width: avatar.size.width * scale, height: avatar.size.height * scale)
            avatar.draw(in: CGRect(
                x: avatarFrame.midX - drawnSize.width / 2,
                y: avatarFrame.midY - drawnSize.height / 2,
                width: drawnSize.width,
                height: drawnSize.height
            ))
            context.restoreGState()
            UIColor.white.withAlphaComponent(0.95).setStroke()
            let border = UIBezierPath(ovalIn: avatarFrame.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = 3
            border.stroke()
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
