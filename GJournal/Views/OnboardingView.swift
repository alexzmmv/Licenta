import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page = 0
    @State private var requestingReminder = false

    private let purple = Color(red: 0.55, green: 0.4, blue: 0.95)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    privacyPage.tag(0)
                    methodPage.tag(1)
                    unlockPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                pageControls
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var privacyPage: some View {
        OnboardingPageView(
            icon: "lock.shield.fill",
            iconColor: Color(red: 0.35, green: 0.65, blue: 1.0),
            title: "Your journal stays with you",
            bodyText: "GJournal runs entirely on your device. Your thoughts never leave — no accounts, no cloud, no tracking. Everything is encrypted and protected by your PIN or Face ID.",
            tag: "PRIVACY FIRST"
        )
    }

    private var methodPage: some View {
        OnboardingPageView(
            icon: "triangle.circle.fill",
            iconColor: purple,
            title: "The FEA method",
            bodyText: "Three guided prompts structure each entry:\n\n**Feel** — describe your emotional state\n**Event** — what triggered or shaped it\n**Action** — what you'll do next\n\nA small habit that builds powerful self-awareness over time.",
            tag: "STRUCTURED JOURNALING"
        )
    }

    private var unlockPage: some View {
        VStack(spacing: 0) {
            OnboardingPageView(
                icon: "chart.xyaxis.line",
                iconColor: Color(red: 0.45, green: 0.85, blue: 0.65),
                title: "Insights grow with your data",
                bodyText: "As you journal, GJournal surfaces patterns invisible to the naked eye — your emotional network, recurring thought loops, and your trajectory through difficult moments.",
                tag: "INTELLIGENT INSIGHTS"
            )

            Button {
                Task { await enableReminderOptIn() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: requestingReminder ? "checkmark.circle.fill" : "bell.badge")
                        .foregroundColor(requestingReminder ? .green : .white)
                    Text(requestingReminder ? "Reminder set" : "Enable daily reminder")
                        .font(.subheadline)
                        .foregroundColor(requestingReminder ? .green : .white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .disabled(requestingReminder)
            .padding(.bottom, 8)

            Text("Optional — you can change this anytime in Settings")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.6))
                .padding(.bottom, 16)
        }
    }

    // MARK: - Controls

    private var pageControls: some View {
        HStack(spacing: 0) {
            // Page dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == page ? purple : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                        .scaleEffect(i == page ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3), value: page)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action button
            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onComplete()
                }
            } label: {
                Text(page < 2 ? "Next" : "Get started")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(purple)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 48)
        .padding(.top, 8)
    }

    // MARK: - Reminder opt-in

    private func enableReminderOptIn() async {
        let granted = await ReminderScheduler.shared.requestPermissionAndEnable()
        if granted { requestingReminder = true }
    }
}

// MARK: - Reusable page template

private struct OnboardingPageView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let bodyText: String
    var tag: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(iconColor)
            }
            .padding(.bottom, 32)

            Text(tag)
                .font(.caption.bold())
                .tracking(2)
                .foregroundColor(iconColor)
                .padding(.bottom, 12)

            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            Text(LocalizedStringKey(self.bodyText))
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 36)

            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
