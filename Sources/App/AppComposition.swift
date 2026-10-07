import Foundation
import Supabase

enum AppComposition {
    @MainActor
    static func makeModel(configuration: BackendConfiguration? = .load()) -> AppModel {
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
