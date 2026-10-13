import Foundation

enum TimelineSizing {
    static let defaultWidth = 204.0
    static func clamped(_ width: Double) -> Double {
        guard width.isFinite else { return defaultWidth }
        return min(360, max(168, width))
    }
}
