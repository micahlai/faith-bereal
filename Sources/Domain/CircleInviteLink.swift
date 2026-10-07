import Foundation

enum CircleInviteLink {
    static let websiteHost = "manna-circle.micahlai.com"
    static let associatedDomain = "applinks:\(websiteHost)"
    static let websiteURL = URL(string: "https://\(websiteHost)")!

    static func normalize(code value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (4...32).contains(code.count),
              code.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (48...57).contains($0.value)
              }) else { return nil }
        return code
    }

    static func webURL(for code: String) -> URL? {
        guard let code = normalize(code: code) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = websiteHost
        components.path = "/join/\(code)"
        return components.url
    }

    static func code(from url: URL) -> String? {
        switch url.scheme?.lowercased() {
        case "https":
            return webCode(from: url)
        case "blessingcircle":
            return customSchemeCode(from: url)
        default:
            return nil
        }
    }

    private static func webCode(from url: URL) -> String? {
        guard url.host?.lowercased() == websiteHost,
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              !url.path.hasSuffix("/") else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "join" else { return nil }
        return normalize(code: String(parts[1]))
    }

    private static func customSchemeCode(from url: URL) -> String? {
        guard url.host?.lowercased() == "join",
              url.path.isEmpty || url.path == "/",
              url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "code",
              let value = queryItems[0].value else { return nil }
        return normalize(code: value)
    }
}
