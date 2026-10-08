import Foundation
import Supabase

enum AppComposition {
    @MainActor
    static func makeModel(configuration: BackendConfiguration? = .load()) -> AppModel {
#if DEBUG
        // An explicit local-backend fence for accessibility UI automation.
        // This launch argument is intentionally unavailable in Release builds.
        if ProcessInfo.processInfo.arguments.contains("--manna-local-ui-test") {
            return AppModel(repository: LocalBlessingRepository())
        }
#endif
        if ProcessInfo.processInfo.environment["BLESSING_CIRCLE_FORCE_LOCAL"] == "1" {
            return AppModel(repository: LocalBlessingRepository())
        }
        guard let configuration else {
#if DEBUG
            return AppModel(repository: LocalBlessingRepository())
#else
            let model = AppModel(repository: LocalBlessingRepository())
            model.loadState = .failed(
                "This release build is missing its hosted service configuration. Install a corrected build."
            )
            return model
#endif
        }
        let client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.publishableKey
        )
        return AppModel(
            repository: SupabaseBlessingRepository(client: client),
            authentication: SupabaseAuthenticationService(client: client)
        )
    }
}
