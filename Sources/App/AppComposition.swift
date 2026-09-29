import Supabase

enum AppComposition {
    @MainActor
    static func makeModel(configuration: BackendConfiguration? = .load()) -> AppModel {
        guard let configuration else {
            return AppModel(repository: LocalBlessingRepository())
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
