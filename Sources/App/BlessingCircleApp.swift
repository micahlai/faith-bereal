import SwiftUI

@main
struct BlessingCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppComposition.makeModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(AppTheme.primary)
                .task {
                    appDelegate.deviceTokenHandler = { token in
                        model.receiveAPNSToken(token)
                    }
                    appDelegate.deviceRegistrationFailureHandler = { message in
                        model.receiveAPNSRegistrationFailure(message)
                    }
                    appDelegate.notificationURLHandler = { url in
                        Task { await model.handleDeepLink(url) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.refreshCurrentCircle() }
                }
        }
    }
}
