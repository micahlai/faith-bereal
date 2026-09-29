import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var lastDeviceToken: String?

    var deviceTokenHandler: ((String) -> Void)? {
        didSet {
            if let lastDeviceToken { deviceTokenHandler?(lastDeviceToken) }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastDeviceToken = token
        deviceTokenHandler?(token)
    }
}
