import Foundation

struct BackendConfiguration: Sendable {
    let supabaseURL: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> BackendConfiguration? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let rawKey = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String else {
            return nil
        }
        let urlString = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty,
              !key.isEmpty,
              !urlString.contains("$("),
              !key.contains("replace_me"),
              let url = URL(string: urlString),
              url.scheme == "https" || url.host == "127.0.0.1" else {
            return nil
        }
        return BackendConfiguration(supabaseURL: url, publishableKey: key)
    }
}
