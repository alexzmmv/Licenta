import SwiftUI

/// A crisis resource shown to the user. `spokenLabel` exists because VoiceOver
/// must read the whole card as one coherent phrase — a person in distress should
/// not have to piece together an icon, a title, a subtitle and a chevron.
struct CrisisResource: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let url: URL?

    var spokenLabel: String { "\(title). \(subtitle)" }
}

/// Region-appropriate crisis lines.
///
/// The previous version hardcoded US-only numbers (`tel:988`, `sms:741741`) for
/// every user on earth, so a person outside the US in crisis was handed numbers
/// that do not connect. Only lines verified for a given region are listed; every
/// other region leads with an international directory rather than a guess.
enum CrisisDirectory {

    private static let blue = Color(red: 0.35, green: 0.65, blue: 1.0)
    private static let green = Color(red: 0.45, green: 0.85, blue: 0.65)
    private static let purple = Color(red: 0.75, green: 0.55, blue: 1.0)

    static let findAHelpline = CrisisResource(
        icon: "globe",
        title: "Find a Helpline",
        subtitle: "Free, confidential helplines in your country",
        tint: purple,
        url: AppLinks.internationalCrisisDirectory
    )

    static let iasp = CrisisResource(
        icon: "mappin.and.ellipse",
        title: "International Association for Suicide Prevention",
        subtitle: "Directory of crisis centres worldwide",
        tint: purple,
        url: URL(string: "https://www.iasp.info/resources/Crisis_Centres/")
    )

    /// Resources for the device's current region, most directly useful first.
    static func resources(for regionCode: String? = Locale.current.region?.identifier) -> [CrisisResource] {
        switch regionCode {
        case "US":
            return [
                CrisisResource(icon: "phone.fill",
                               title: "988 Suicide & Crisis Lifeline",
                               subtitle: "Call or text 988 — available 24/7",
                               tint: blue,
                               url: URL(string: "tel:988")),
                CrisisResource(icon: "message.fill",
                               title: "Crisis Text Line",
                               subtitle: "Text HOME to 741741 — free, 24/7",
                               tint: green,
                               url: URL(string: "sms:741741&body=HOME")),
                findAHelpline
            ]
        case "CA":
            return [
                CrisisResource(icon: "phone.fill",
                               title: "9-8-8 Suicide Crisis Helpline",
                               subtitle: "Call or text 988 — available 24/7",
                               tint: blue,
                               url: URL(string: "tel:988")),
                findAHelpline
            ]
        case "GB", "IE":
            return [
                CrisisResource(icon: "phone.fill",
                               title: "Samaritans",
                               subtitle: "Call 116 123 free, any time, day or night",
                               tint: blue,
                               url: URL(string: "tel:116123")),
                CrisisResource(icon: "message.fill",
                               title: "Shout",
                               subtitle: "Text SHOUT to 85258 — free, 24/7",
                               tint: green,
                               url: URL(string: "sms:85258&body=SHOUT")),
                findAHelpline
            ]
        case "AU":
            return [
                CrisisResource(icon: "phone.fill",
                               title: "Lifeline Australia",
                               subtitle: "Call 13 11 14 — available 24/7",
                               tint: blue,
                               url: URL(string: "tel:131114")),
                findAHelpline
            ]
        default:
            // No verified line for this region — never invent a number.
            return [findAHelpline, iasp]
        }
    }
}

struct CrisisResourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let resources = CrisisDirectory.resources()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 16)

                        header

                        VStack(spacing: 14) {
                            ForEach(resources) { resource in
                                crisisCard(resource)
                            }
                        }
                        .padding(.horizontal, 20)

                        Text("GJournal is a personal wellness journal, not a medical or therapeutic service. If you're in immediate danger, please call your local emergency number.")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer(minLength: 24)
                    }
                }
            }
            .navigationTitle("Support Resources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.55))
                .accessibilityHidden(true)

            Text("You're not alone")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("If you're going through a difficult time, these free, confidential resources are available around the clock.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func crisisCard(_ resource: CrisisResource) -> some View {
        Button {
            if let url = resource.url { openURL(url) }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(resource.tint.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: resource.icon)
                        .font(.title3)
                        .foregroundColor(resource.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(resource.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    Text(resource.subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(resource.tint.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        // One element, one spoken phrase — not four fragments and a chevron.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(resource.spokenLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(hint(for: resource)))
    }

    private func hint(for resource: CrisisResource) -> String {
        guard let scheme = resource.url?.scheme else { return "Opens this resource" }
        switch scheme {
        case "tel":  return "Starts a phone call"
        case "sms":  return "Opens a text message"
        default:     return "Opens in your browser"
        }
    }
}

#Preview {
    CrisisResourcesView()
}
