import Foundation

/// External URLs surfaced in the UI.
///
/// App Review requires a paywall offering in-app purchase to link to both a
/// Terms of Use (EULA) and a Privacy Policy (Guideline 3.1.2 / 5.1.1). Missing
/// links are a common rejection reason.
enum AppLinks {

    /// Apple's standard EULA. Developers who do not supply a custom licence
    /// agreement are expected to use this exact URL, so it is correct as-is.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// ⚠️ REPLACE BEFORE SUBMISSION — must point at a real, publicly reachable
    /// page you host. App Store Connect requires the same URL in the app's
    /// metadata, and Review will follow it. There is no generic fallback for
    /// this one the way there is for the EULA.
    static let privacyPolicy = URL(string: "https://example.com/gjournal/privacy")!

    /// ⚠️ REPLACE BEFORE SUBMISSION — shown in Settings → Support.
    static let supportEmail = URL(string: "mailto:support@example.com")!

    /// International crisis-line directory, used as the non-US fallback in
    /// CrisisResourcesView where the hardcoded 988 / 741741 numbers do not apply.
    static let internationalCrisisDirectory = URL(string: "https://findahelpline.com")!

    /// True when a link still points at the placeholder host and must not ship.
    static var hasUnconfiguredLinks: Bool {
        [privacyPolicy, supportEmail].contains { $0.absoluteString.contains("example.com") }
    }
}
