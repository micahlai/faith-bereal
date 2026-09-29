import SwiftUI

@main
struct BlessingCircleApp: App {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppComposition.makeModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(AppTheme.iris)
        }
    }
}
