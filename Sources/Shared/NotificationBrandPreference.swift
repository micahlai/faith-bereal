import Foundation

enum NotificationBrandPreference {
    static let appGroupIdentifier = "group.app.blessingcircle.shared"
    static let preferenceKey = "notification.brand.icon.v1"

    static func save(_ preference: String) {
        defaults.set(preference, forKey: preferenceKey)
    }

    static func logoResourceName(prefersDarkAppearance: Bool) -> String {
        switch defaults.string(forKey: preferenceKey) {
        case "cream":
            "NotificationLogo"
        case "midnight":
            "NotificationLogoDark"
        default:
            prefersDarkAppearance ? "NotificationLogoDark" : "NotificationLogo"
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
