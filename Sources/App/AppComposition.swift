import Foundation
import Supabase

enum AppComposition {
    @MainActor
    static func makeModel(configuration: BackendConfiguration? = .load()) -> AppModel {
        let diagnosticStore = BackendDiagnosticStore(defaultEnabled:
            Bundle.main.object(forInfoDictionaryKey: "MANNA_DIAGNOSTICS_DEFAULT_ENABLED") as? Bool ?? false)
        let localCollection = DiagnosticCollectionController(store: diagnosticStore)
#if DEBUG
        // An explicit local-backend fence for accessibility UI automation.
        // This launch argument is intentionally unavailable in Release builds.
        if ProcessInfo.processInfo.arguments.contains("--manna-local-ui-test") {
            let photoURL = ProcessInfo.processInfo.arguments.contains("--manna-photo-ui-test")
                ? PhotoViewerUITestFixture.makePhoto() : nil
            let settingsRole = ProcessInfo.processInfo.environment["MANNA_CIRCLE_SETTINGS_TEST_ROLE"]
            return AppModel(repository: LocalBlessingRepository(seedPhotoURL: photoURL,
                settingsTestRole: settingsRole), diagnosticCollection: localCollection)
        }
#endif
        if ProcessInfo.processInfo.environment["BLESSING_CIRCLE_FORCE_LOCAL"] == "1" {
            return AppModel(repository: LocalBlessingRepository(), diagnosticCollection: localCollection)
        }
        guard let configuration else {
#if DEBUG
            return AppModel(repository: LocalBlessingRepository(), diagnosticCollection: localCollection)
#else
            let model = AppModel(repository: LocalBlessingRepository(), diagnosticCollection: localCollection)
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
            authentication: SupabaseAuthenticationService(client: client),
            diagnosticCollection: DiagnosticCollectionController(store: diagnosticStore, uploader:
                SupabaseDiagnosticUploader(client: client, configuration: configuration))
        )
    }
}
