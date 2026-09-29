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
                .tint(AppTheme.iris)
                .task {
                    appDelegate.deviceTokenHandler = { token in
                        model.receiveAPNSToken(token)
                    }
                }
        }
    }
}
