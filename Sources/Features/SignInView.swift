import AuthenticationServices
import CryptoKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var rawNonce = ""

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 68, weight: .light))
                    .foregroundStyle(AppTheme.iris)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("manna circle")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("A shared daily pause for what is good.")
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                SignInWithAppleButton(.continue) { request in
                    rawNonce = UUID().uuidString
                    request.nonce = SHA256.hash(data: Data(rawNonce.utf8))
                        .map { String(format: "%02x", $0) }
                        .joined()
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                Text("Your Apple identity is used only for your private circles.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)
            .padding(32)
        }
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            if case let .failure(error) = result { model.message = error.localizedDescription }
            return
        }
        let fullName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
        Task {
            await model.signInWithApple(
                idToken: token,
                rawNonce: rawNonce,
                fullName: fullName
            )
        }
    }
}
