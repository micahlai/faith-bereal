import SwiftUI

@main
struct BlessingCircleApp: App {
    @State private var model = AppModel(repository: LocalBlessingRepository())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(AppTheme.iris)
        }
    }
}

