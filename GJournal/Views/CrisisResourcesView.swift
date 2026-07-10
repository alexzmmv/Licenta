import SwiftUI

struct CrisisResourcesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 16)

                        VStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.55))

                            Text("You're not alone")
                                .font(.title2.bold())
                                .foregroundColor(.white)

                            Text("If you're going through a difficult time, these free, confidential resources are available around the clock.")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        VStack(spacing: 14) {
                            crisisCard(
                                icon: "phone.fill",
                                title: "988 Suicide & Crisis Lifeline",
                                subtitle: "Call or text 988 — available 24/7",
                                color: Color(red: 0.35, green: 0.65, blue: 1.0),
                                url: URL(string: "tel:988")
                            )

                            crisisCard(
                                icon: "message.fill",
                                title: "Crisis Text Line",
                                subtitle: "Text HOME to 741741 — free, 24/7",
                                color: Color(red: 0.45, green: 0.85, blue: 0.65),
                                url: URL(string: "sms:741741&body=HOME")
                            )

                            crisisCard(
                                icon: "globe",
                                title: "International Association for Suicide Prevention",
                                subtitle: "Find a crisis center near you",
                                color: Color(red: 0.75, green: 0.55, blue: 1.0),
                                url: URL(string: "https://www.iasp.info/resources/Crisis_Centres/")
                            )
                        }
                        .padding(.horizontal, 20)

                        Text("GJournal is a personal wellness journal, not a medical or therapeutic service. If you're in immediate danger, please call 911 or your local emergency number.")
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

    private func crisisCard(icon: String, title: String, subtitle: String, color: Color, url: URL?) -> some View {
        Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
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
                            .stroke(color.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CrisisResourcesView()
}
