import UIKit
@preconcurrency import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var lastDeviceToken: String?
    private var pendingNotificationURL: URL?

    var deviceTokenHandler: ((String) -> Void)? {
        didSet {
            if let lastDeviceToken { deviceTokenHandler?(lastDeviceToken) }
        }
    }
    var deviceRegistrationFailureHandler: ((String) -> Void)?

    var notificationURLHandler: ((URL) -> Void)? {
        didSet {
            if let pendingNotificationURL {
                self.pendingNotificationURL = nil
                notificationURLHandler?(pendingNotificationURL)
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastDeviceToken = token
        deviceTokenHandler?(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        deviceRegistrationFailureHandler?(error.localizedDescription)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let route = response.notification.request.content.userInfo["route"] as? String
        let url = route.flatMap(URL.init(string:))
        completionHandler()
        guard let url else { return }
        Task { @MainActor [weak self] in
            self?.deliverNotificationURL(url)
        }
    }

    private func deliverNotificationURL(_ url: URL) {
        if let notificationURLHandler {
            notificationURLHandler(url)
        } else {
            pendingNotificationURL = url
        }
    }
}
