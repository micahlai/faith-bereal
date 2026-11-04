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
                    .accessibilityIdentifier("deletion.acknowledgement")
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--manna-safety-ui-test"),
                   model.accountSafety is SafetyUITestService {
                    Button("Confirm local test deletion") {
                        Task { await model.requestAccountDeletion(appleCode: "local-ui-only") }
                    }.frame(minHeight: 52).disabled(!confirmed || model.isDeletingAccount)
                        .accessibilityIdentifier("deletion.localConfirmation")
                } else {
                    appleConfirmation
                }
#else
                appleConfirmation
#endif
                Text("Confirm with the same Apple account you use for manna. This also revokes manna’s Apple sign-in authorization.").font(.footnote)
                if model.isDeletingAccount { ProgressView("Requesting deletion…") }
                if let error = model.accountDeletionRequestError {
                    Text(error).foregroundStyle(AppTheme.missed).accessibilityIdentifier("deletion.requestError")
                    Button("Check deletion status") { Task { await model.checkAccountDeletion() } }.frame(minWidth: 44, minHeight: 44)
                    if let status = model.accountDeletionStatusMessage { Text(status).accessibilityIdentifier("deletionStatus") }
                }
            }
        }.navigationTitle("Delete account")
    }

    private var appleConfirmation: some View {
        SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = []
                } onCompletion: { result in
                    guard case let .success(auth) = result,
                          let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let code = credential.authorizationCode,
                          let string = String(data: code, encoding: .utf8) else {
                        model.accountDeletionRequestError = "Apple confirmation was cancelled or unavailable. No new deletion request was sent."
                        return
                    }
                    Task { await model.requestAccountDeletion(appleCode: string) }
                }.frame(height: 52).disabled(!confirmed || model.isDeletingAccount)
    }
}
struct AccountDeletionPendingView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Account deletion requested").font(.title)
                        .accessibilityIdentifier("deletion.heading")
                    Text("Your account is unavailable while cleanup runs. Copies in both media stores are checked before the account is removed. Interrupted copies can require at least 30 minutes; an outage can take longer. Contact support if you need the status of your request.")
                        .accessibilityIdentifier("deletion.explanation")
                    Link("Contact privacy support", destination: URL(string: "mailto:\(PrivacyContent.contact)")!)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    if let status = model.accountDeletionStatusMessage { Text(status).accessibilityIdentifier("deletionStatus") }
                    Button("Check deletion status") { Task { await model.checkAccountDeletion() } }
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    Button("Sign out") { Task { await model.signOut() } }
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    NavigationLink("Privacy policy") { PrivacyPolicyView() }.frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding().frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("deletion.pendingScroll")
            .background(AppTheme.canvas)
            .foregroundStyle(AppTheme.ink)
        }
    }
}
struct BlockedUsersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var users: [BlockedUser] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(AppTheme.missed).accessibilityIdentifier("safety.blockedError")
                Button("Retry") { Task { await load() } }.frame(minWidth: 44, minHeight: 44)
            } else if loading {
                ProgressView("Loading blocked users…")
            } else if users.isEmpty {
                Text("No blocked users")
            }
            ForEach(users) { user in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { Text(user.display_name); unblock(user) }
                } else {
                    HStack { Text(user.display_name); Spacer(); unblock(user) }
                }
            }
        }.navigationTitle("Blocked users").task { await load() }
    }
    private func unblock(_ user: BlockedUser) -> some View {
        Button("Unblock") {
            Task {
                do {
                    try await model.accountSafety.setBlock(userID: user.id, blocked: false)
                    model.restoreBlockedAuthor(user.id)
                    await load()
                } catch { self.error = "Could not unblock. Try again." }
            }
        }.frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("safety.unblock.\(user.id.uuidString)")
    }
    private func load() async {
        loading = true
        defer { loading = false }
        do { users = try await model.accountSafety.blockedUsers(); error = nil }
        catch { self.error = "Could not load blocked users. Try again." }
    }
}
struct ContentSafetyActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let authorID: UUID
    var blessingID: UUID?
    var responseID: UUID?
    @State private var reporting = false
    @State private var blocking = false
    @State private var blockFailed = false
    var body: some View {
        if authorID != model.currentUser?.id {
            Menu("Safety", systemImage: "ellipsis.circle") {
                Button("Report content", systemImage: "flag") { reporting = true }
                Button("Block user", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { blocking = true }
            }.frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier(responseID == nil ? "safety.blessing" : "safety.response")
            .sheet(isPresented: $reporting) { ContentReportView(blessingID: blessingID, responseID: responseID) }
            .confirmationDialog("Block this user?", isPresented: $blocking, titleVisibility: .visible) {
                Button("Block user", role: .destructive) {
                    Task {
                        do {
                            try await model.accountSafety.setBlock(userID: authorID, blocked: true)
                            await model.clearBlockedPresentation(authorID: authorID)
                            dismiss()
                        } catch { blockFailed = true }
                    }
                }
            } message: { Text("You will not see each other’s posts or responses in the live service. Previously downloaded links and other people’s exported copies may remain. Unblock in User settings.") }
            .alert("Could not block user", isPresented: $blockFailed) { Button("OK", role: .cancel) {} }
                message: { Text("Could not block this user. Try again.") }
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
    @FocusState private var detailsFocused: Bool
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(["harassment", "sexual", "hate", "violence", "privacy", "spam", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                }.pickerStyle(.navigationLink)
                    .frame(minHeight: 44).accessibilityIdentifier("safety.reportReason")
                TextField("Details (optional)", text: $detail, axis: .vertical).lineLimit(3...8)
                    .accessibilityIdentifier("safety.reportDetails")
                    .focused($detailsFocused)
                    .onChange(of: detail) { _, value in detail = String(value.prefix(1000)) }
                Text("Reports are private to the developer, who can review the reported content and take action. Do not include unnecessary personal information. For urgent danger, contact local emergency services.")
                if let error { Text(error).foregroundStyle(AppTheme.missed).accessibilityIdentifier("safety.reportError") }
                Button(sending ? "Sending…" : "Send report") {
                    sending = true
                    Task {
                        do { try await model.accountSafety.report(blessingID: blessingID, responseID: responseID, reason: reason, detail: detail); dismiss(); model.message = "Report received for review. You can also block this user." }
                        catch { self.error = "Could not send your report. Try again or contact support." }
                        sending = false
                    }
                }.disabled(sending).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("safety.reportSend")
            }.navigationTitle("Report content")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Cancel")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { detailsFocused = false } }
                }
        }
    }
}
