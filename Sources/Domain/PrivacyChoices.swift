import Foundation

struct PrivacyChoices: Equatable, Sendable {
    var ageConfirmed = false
    var sharingConsent = false
    var diagnostics = false
    var canContinue: Bool { ageConfirmed && sharingConsent }
}
