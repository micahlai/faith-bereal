import SwiftUI

@main
struct BlessingCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                    appDelegate.notificationURLHandler = { url in
                        Task { await model.handleDeepLink(url) }
                    }
                }
        }
    }
}
