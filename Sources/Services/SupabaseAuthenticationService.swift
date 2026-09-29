import Foundation
import Supabase

actor SupabaseAuthenticationService: AuthenticationProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func hasSession() async -> Bool {
        (try? await client.auth.session) != nil
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )
        if let fullName, !fullName.isEmpty {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
