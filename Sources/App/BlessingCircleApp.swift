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
                    appDelegate.foregroundNotificationHandler = { url in
                        Task { await model.handleForegroundNotification(url) }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .mannaSavingNetworkChanged).receive(on: RunLoop.main)) { _ in
                    if scenePhase == .active { model.resumeAutomaticSavingAfterNetworkChange() }
                }
                .onChange(of: scenePhase) { _, phase in
                    model.diagnosticCollection.setForeground(phase == .active)
                    guard phase == .active else { return }
                    Task {
                        await model.refreshCurrentCircle(force: false)
                        await model.diagnosticCollection.sendNow(automatic: true)
                    }
                }
        }
    }
}
