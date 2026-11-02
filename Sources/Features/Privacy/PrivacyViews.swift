import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(PrivacyContent.sections, id: \.0) { title, text in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline)
                        Text(text).font(.body).textSelection(.enabled)
                    }
                }
                Link("Privacy contact", destination: URL(string: "mailto:\(PrivacyContent.contact)")!)
                    .frame(minHeight: 44)
            }.padding().frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }.navigationTitle("Privacy policy").navigationBarTitleDisplayMode(.inline)
    }
}

struct LaunchPrivacyView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("privacy.acceptedVersion") private var acceptedVersion = ""
    @State private var ageConfirmed = false
    @State private var sharingConsent = false
    @State private var diagnostics = false
    let onContinue: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("manna circle is for people 13 and older in the United States.")
                    Toggle("I am at least 13 years old", isOn: $ageConfirmed).accessibilityIdentifier("privacy.age")
                    NavigationLink("Read privacy policy") { PrivacyPolicyView() }
                    Text("Your profile, posts and selected media go to our service providers and authorized circle members. Faith posts may reveal sensitive beliefs. Supabase runs accounts and storage; Cloudflare stores media copies; Apple provides sign-in, notifications and optional speech processing.")
                    Toggle("I agree to this use and sharing of my information", isOn: $sharingConsent).accessibilityIdentifier("privacy.sharing")
                } header: { Text("Your privacy") }
                Section {
                    Toggle("Share diagnostic data", isOn: $diagnostics).accessibilityIdentifier("privacy.diagnostics")
                    Text("Optional and off by default. Sends account-linked performance timings, sizes, short failure codes and app build for reliability. No post text or media. Reports are kept for 14 days; change your choice anytime in User settings.")
                }
                Section("Community rules") { Text(PrivacyContent.communityRules) }
                Section {
                    Button("Agree and continue") {
                        Task {
                            if model.currentUser == nil {
                                UserDefaults.standard.set(diagnostics, forKey: "privacy.initialDiagnosticConsent")
                            } else {
                                await model.diagnosticCollection.setEnabled(diagnostics)
                            }
                            acceptedVersion = PrivacyContent.version
                            onContinue()
                        }
                    }.disabled(!ageConfirmed || !sharingConsent).frame(minHeight: 44)
                    .accessibilityIdentifier("privacy.continue")
                } footer: { Text("Continuing also agrees to the community rules. If you are under 13, close the app without signing in. Device permissions are requested separately when needed.") }
            }.navigationTitle("Before you begin")
        }.interactiveDismissDisabled()
    }
}

struct PrivacySettingsSection: View {
    var body: some View {
        Section("Privacy and safety") {
            NavigationLink("Privacy policy") { PrivacyPolicyView() }
            NavigationLink("Blocked users") { BlockedUsersView() }
            NavigationLink("Community rules") { ScrollView { Text(PrivacyContent.communityRules).padding() }.navigationTitle("Community rules") }
            Link("Contact support", destination: URL(string: "mailto:\(PrivacyContent.contact)")!).frame(minHeight: 44)
            Text("No advertising tracking. Diagnostic sharing is optional. Permissions can be changed in iOS Settings.").font(.footnote)
        }
    }
}
