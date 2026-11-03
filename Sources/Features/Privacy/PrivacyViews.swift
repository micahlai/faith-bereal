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

struct PrivacyOnboardingPage: View {
    @Binding var choices: PrivacyChoices
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "hand.raised.fill").font(.largeTitle).foregroundStyle(AppTheme.primary)
                Text("A private place to share").font(.largeTitle.weight(.bold)).foregroundStyle(AppTheme.ink)
                Text("Take a moment to understand how your information is used before signing in or sharing with a circle.")
                    .font(.title3).foregroundStyle(AppTheme.secondaryInk)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("For people 13 and older").font(.headline)
                Text("manna circle is initially available in the United States. If you are under 13, close the app without signing in.")
                consentToggle("I am at least 13 years old", identifier: "privacy.age", isOn: $choices.ageConfirmed)
            }.blessingCard()
            VStack(alignment: .leading, spacing: 16) {
                Text("Your information and your circle").font(.headline)
                Text("Your profile, posts and selected media go to our service providers and authorized circle members. Faith posts may reveal sensitive beliefs. Supabase runs accounts and storage; Cloudflare stores media copies; Apple provides sign-in, notifications and optional speech processing.")
                NavigationLink("Read privacy policy") { PrivacyPolicyView() }.frame(minHeight: 44)
                    .foregroundStyle(AppTheme.primary)
                consentToggle("I agree to this use and sharing of my information", identifier: "privacy.sharing", isOn: $choices.sharingConsent)
            }.blessingCard()
            VStack(alignment: .leading, spacing: 16) {
                Text("Help improve manna, if you choose").font(.headline)
                consentToggle("Share diagnostic data", identifier: "privacy.diagnostics", isOn: $choices.diagnostics)
                Text("Optional and off by default. Sends account-linked performance timings, sizes, short failure codes and app build for reliability. No post text or media. Reports are kept for 14 days; change your choice anytime in User settings.")
                    .foregroundStyle(AppTheme.secondaryInk)
            }.blessingCard()
            VStack(alignment: .leading, spacing: 16) {
                Text("Care for your community").font(.headline)
                Text(PrivacyContent.communityRules)
                Text("Continuing also agrees to these community rules. Device permissions are requested separately when needed.")
                    .foregroundStyle(AppTheme.secondaryInk)
            }.blessingCard()
        }
    }

    @ViewBuilder
    private func consentToggle(_ title: String, identifier: String, isOn: Binding<Bool>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Toggle(title, isOn: isOn).labelsHidden().accessibilityLabel(title)
                    .accessibilityIdentifier(identifier).frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        } else {
            Toggle(title, isOn: isOn).frame(minHeight: 44).accessibilityIdentifier(identifier)
        }
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
