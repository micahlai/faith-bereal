import Foundation
import Supabase
#if DEBUG
import AVFoundation
#endif

enum AppComposition {
    @MainActor
    static func makeModel(configuration: BackendConfiguration? = .load()) -> AppModel {
        let diagnosticStore = BackendDiagnosticStore(defaultEnabled:
            Bundle.main.object(forInfoDictionaryKey: "MANNA_DIAGNOSTICS_DEFAULT_ENABLED") as? Bool ?? false)
        let localCollection = DiagnosticCollectionController(store: diagnosticStore)
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--manna-offline-saved-ui-test"),
           let session = ProcessInfo.processInfo.environment["BLESSING_CIRCLE_SAVING_TEST_SESSION"],
           let sessionID = UUID(uuidString: session) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineSavedUITest-\(sessionID)")
            let store = SavedBlessingStore(root: root)
            return AppModel(repository: LocalBlessingRepository(),
                authentication: OfflineSavedUITestAuthentication(store: store, root: root),
                savedBlessingStore: store, diagnosticCollection: localCollection,
                metadataStore: CircleMetadataStore(directory: root.appendingPathComponent("metadata")),
                registersForRemoteNotifications: false, runsBackgroundRefreshes: false)
        }
        // An explicit local-backend fence for accessibility UI automation.
        // This launch argument is intentionally unavailable in Release builds.
        if ProcessInfo.processInfo.arguments.contains("--manna-local-ui-test")
            || ProcessInfo.processInfo.arguments.contains("--manna-loading-ui-test") {
            let photoURL = ProcessInfo.processInfo.arguments.contains("--manna-photo-ui-test")
                ? PhotoViewerUITestFixture.makePhoto() : nil
            let settingsRole = ProcessInfo.processInfo.environment["MANNA_CIRCLE_SETTINGS_TEST_ROLE"]
            return AppModel(repository: LocalBlessingRepository(seedPhotoURL: photoURL,
                settingsTestRole: settingsRole,
                streakTestFixture: ProcessInfo.processInfo.arguments.contains("--manna-streak-ui-test"),
                timelineTestFixture: ProcessInfo.processInfo.arguments.contains("--manna-timeline-ui-test")), diagnosticCollection: localCollection)
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

#if DEBUG
/// Offline-only UI fixture: no authenticated session or repository reads are available.
private actor OfflineSavedUITestAuthentication: AuthenticationProviding {
    let store: SavedBlessingStore
    let root: URL
    let accountID = UUID(uuidString: "AAAAAAAA-1111-2222-3333-444444444444")!
    init(store: SavedBlessingStore, root: URL) { self.store = store; self.root = root }
    func cachedUserID() async -> UUID? {
        do {
            if try await store.load(userID: accountID).isEmpty {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let source = root.appendingPathComponent("source.caf")
                let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
                buffer.frameLength = buffer.frameCapacity
                for index in 0..<Int(buffer.frameLength) {
                    buffer.floatChannelData?[0][index] = Float(sin(Double(index) * 0.05)) * 0.01
                }
                try autoreleasepool {
                    let file = try AVAudioFile(forWriting: source, settings: format.settings)
                    try file.write(from: buffer)
                }
                let blessing = Blessing(id: UUID(), circleID: UUID(), promptID: UUID(), authorID: accountID,
                    captureMode: .voice, body: "Offline saved voice fixture", audioURL: source, videoURL: nil,
                    submittedAt: .now, isLate: false, scriptureReference: nil)
                let response = BlessingResponse(id: UUID(), blessingID: blessing.id, circleID: blessing.circleID,
                    authorID: accountID, mode: .voice, body: "Offline saved response", audioURL: source, submittedAt: .now)
                let saved = try await store.save(blessing: blessing, responses: [response], userID: accountID)
                // Reproduce the older archive's .data filenames for both recordings.
                let directory = root.appendingPathComponent(accountID.uuidString).appendingPathComponent(blessing.id.uuidString)
                let manifest = directory.appendingPathComponent("blessing.json")
                var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
                var files = saved.files
                for (key, name) in files {
                    let legacy = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + ".data"
                    try FileManager.default.moveItem(at: directory.appendingPathComponent(name), to: directory.appendingPathComponent(legacy))
                    files[key] = legacy
                }
                json["files"] = files
                try JSONSerialization.data(withJSONObject: json).write(to: manifest, options: .atomic)
                try? FileManager.default.removeItem(at: source)
            }
            return accountID
        } catch { return nil }
    }
    func hasSession() async -> Bool { false }
    func currentUserID() async -> UUID? { nil }
    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws { }
    func signOut() async throws { }
}
#endif
