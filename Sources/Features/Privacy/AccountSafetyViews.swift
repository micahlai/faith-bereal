import AuthenticationServices
import SwiftUI

struct AccountDeletionView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmed = false
    var body: some View {
        Form {
            Section {
                Text("Delete your account").font(.title2)
                Text("This permanently removes your profile, authored blessings and responses, memberships, and owned media from the active service, including both media stores. Leadership passes to a remaining member; a circle with no remaining member is deleted. Other people’s saved or exported copies cannot be recalled.")
                Text("Deletion is queued and may take time if a provider is unavailable or a copy is still finishing. Access is disabled after acceptance. We verify media cleanup before removing your account. You cannot undo an accepted request.")
                Toggle("I understand and want to delete my account", isOn: $confirmed)
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    guard case let .success(auth) = result,
                          let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let code = credential.authorizationCode,
                          let string = String(data: code, encoding: .utf8) else {
                        model.message = "Apple confirmation was cancelled or unavailable. No new deletion request was sent."
                        return
                    }
                    Task { await model.requestAccountDeletion(appleCode: string) }
                }.frame(height: 52).disabled(!confirmed || model.isDeletingAccount)
                Text("Confirm with the same Apple account you use for manna. This also revokes manna’s Apple sign-in authorization.").font(.footnote)
                if model.isDeletingAccount { ProgressView("Requesting deletion…") }
            }
        }.navigationTitle("Delete account")
    }
}
struct AccountDeletionPendingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Account deletion requested").font(.title)
                Text("Your account is unavailable while cleanup runs. Copies in both media stores are checked before the account is removed. Interrupted copies can require at least 30 minutes; an outage can take longer. Contact support if you need the status of your request.")
                Link("Contact privacy support", destination: URL(string: "mailto:\(PrivacyContent.contact)")!).frame(minHeight: 44)
                if let status = model.accountDeletionStatusMessage { Text(status).accessibilityIdentifier("deletionStatus") }
                Button("Check deletion status") { Task { await model.checkAccountDeletion() } }.frame(minHeight: 44)
                Button("Sign out") { Task { await model.signOut(); model.accountDeletionPending = false } }.frame(minHeight: 44)
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
            }.padding().frame(maxWidth: 680)
        }
    }
}
struct BlockedUsersView: View {
    @Environment(AppModel.self) private var model
    @State private var users: [BlockedUser] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error) }
            if users.isEmpty { Text("No blocked users") }
            ForEach(users) { user in
                HStack {
                    Text(user.display_name)
                    Spacer()
                    Button("Unblock") { Task { do { try await model.accountSafety.setBlock(userID: user.id, blocked: false); model.restoreBlockedAuthor(user.id); await load() } catch { self.error = "Could not unblock. Try again." } } }.frame(minHeight: 44)
                }
            }
        }.navigationTitle("Blocked users").task { await load() }
    }
    private func load() async { do { users = try await model.accountSafety.blockedUsers() } catch { self.error = "Could not load blocked users. Try again." } }
}
struct ContentSafetyActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let authorID: UUID
    var blessingID: UUID?
    var responseID: UUID?
    @State private var reporting = false
    @State private var blocking = false
    var body: some View {
        if authorID != model.currentUser?.id {
            Menu("Safety", systemImage: "ellipsis.circle") {
                Button("Report content", systemImage: "flag") { reporting = true }
                Button("Block user", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { blocking = true }
            }.frame(minWidth: 44, minHeight: 44)
            .sheet(isPresented: $reporting) { ContentReportView(blessingID: blessingID, responseID: responseID) }
            .confirmationDialog("Block this user?", isPresented: $blocking, titleVisibility: .visible) {
                Button("Block user", role: .destructive) {
                    Task {
                        do {
                            try await model.accountSafety.setBlock(userID: authorID, blocked: true)
                            await model.clearBlockedPresentation(authorID: authorID)
                            dismiss()
                        } catch { model.message = "Could not block this user. Try again." }
                    }
                }
            } message: { Text("You will not see each other’s posts or responses in the live service. Previously downloaded links and other people’s exported copies may remain. Unblock in User settings.") }
        }
    }
}
struct ContentReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let blessingID: UUID?
    let responseID: UUID?
    @State private var reason = "harassment"
    @State private var detail = ""
    @State private var sending = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(["harassment", "sexual", "hate", "violence", "privacy", "spam", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                TextField("Details (optional)", text: $detail, axis: .vertical).lineLimit(3...8)
                    .onChange(of: detail) { _, value in detail = String(value.prefix(1000)) }
                Text("Reports are private to the developer, who can review the reported content and take action. Do not include unnecessary personal information. For urgent danger, contact local emergency services.")
                if let error { Text(error).foregroundStyle(.red) }
                Button(sending ? "Sending…" : "Send report") {
                    sending = true
                    Task {
                        do { try await model.accountSafety.report(blessingID: blessingID, responseID: responseID, reason: reason, detail: detail); dismiss(); model.message = "Report received for review. You can also block this user." }
                        catch { self.error = "Could not send your report. Try again or contact support." }
                        sending = false
                    }
                }.disabled(sending).frame(minHeight: 44)
            }.navigationTitle("Report content").toolbar { Button("Cancel") { dismiss() } }
        }
    }
}
