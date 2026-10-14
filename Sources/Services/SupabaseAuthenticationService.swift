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

    func currentUserID() async -> UUID? { try? await client.auth.session.user.id }

    func signInWithApple(idToken: String, rawNonce: String, fullName: String?) async throws {
        let span = BackendDiagnostics.shared.beginRequest(.auth)
        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
            span.finish()
        } catch {
            span.finish(error: error)
            throw error
        }
        if let fullName, !fullName.isEmpty {
            let updateSpan = BackendDiagnostics.shared.beginRequest(.auth)
            do {
                _ = try await client.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
                updateSpan.finish()
            } catch { updateSpan.finish(error: error) }
        }
    }

    func signOut() async throws {
        let span = BackendDiagnostics.shared.beginRequest(.auth)
        do {
            try await client.auth.signOut()
            span.finish()
        } catch {
            span.finish(error: error)
            throw error
        }
    }
}
