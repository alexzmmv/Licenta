import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(EntitlementManager.self) var entitlementManager
    @Environment(\.dismiss) var dismiss

    private let accentPurple = Color(red: 0.55, green: 0.4, blue: 0.95)
    private let accentBlue = Color(red: 0.2, green: 0.7, blue: 0.9)
    private let accentOrange = Color(red: 0.9, green: 0.55, blue: 0.25)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [Color.clear, Color(red: 0.18, green: 0.08, blue: 0.38).opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 400)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    featuresSection
                    purchaseSection
                    privacyNote
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
        }
        .navigationBarHidden(true)
        .task {
            await entitlementManager.loadProducts()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentPurple.opacity(0.35), accentBlue.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                Text("✨")
                    .font(.system(size: 44))
            }

            VStack(spacing: 8) {
                Text("GJournal Insights")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Unlock deep self-understanding.\nYour data never leaves this device.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "point.3.connected.trianglepath.dotted",
                color: accentPurple,
                title: "Psychological Network",
                description: "See how your emotions and behaviours connect — powered by real partial-correlation math."
            )
            Divider().background(Color.white.opacity(0.07))
            featureRow(
                icon: "waveform.path",
                color: accentBlue,
                title: "Trajectory Analysis",
                description: "Track emotional loops, recovery velocity, and exploration across time."
            )
            Divider().background(Color.white.opacity(0.07))
            featureRow(
                icon: "magnifyingglass.circle",
                color: accentOrange,
                title: "Smart Semantic Search",
                description: "Find entries by meaning, not just keywords — hybrid BM25 + vector search."
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            if let error = entitlementManager.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await entitlementManager.purchase() }
            } label: {
                Group {
                    if entitlementManager.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                            if let product = entitlementManager.product {
                                Text("Unlock for \(product.displayPrice)")
                            } else {
                                Text("Unlock Insights")
                            }
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.7, green: 0.3, blue: 0.95), accentPurple],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: accentPurple.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .disabled(entitlementManager.isLoading)

            Button {
                Task { await entitlementManager.restore() }
            } label: {
                Text("Restore Purchase")
                    .font(.subheadline)
                    .foregroundColor(accentPurple)
            }
            .disabled(entitlementManager.isLoading)
        }
    }

    // MARK: - Privacy note

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundColor(.gray)
            Text("One-time purchase · Family Sharing · No subscription · 100% on-device")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 8)
    }
}
