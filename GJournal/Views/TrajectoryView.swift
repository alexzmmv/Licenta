import SwiftUI

/// Trajectory biomarkers dashboard (Pillar B). Wellness framing only — "patterns", never
/// diagnosis or recovery claims. Surfaces three cards: Rumination (real persistent-homology
/// loop persistence), Exploration (flare index), and Semantic Recovery Velocity.
struct TrajectoryView: View {
    @Environment(\.dismiss) private var dismiss
    let metrics: TrajectoryMetrics?

    private let teal = Color(red: 0.2, green: 0.7, blue: 0.9)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let m = metrics {
                    content(m)
                } else {
                    empty
                }
            }
            .navigationTitle("Trajectory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Content

    private func content(_ m: TrajectoryMetrics) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                summary(m)

                MetricCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Rumination",
                    accent: Color(red: 0.85, green: 0.45, blue: 0.55),
                    value: ruminationLevel(m),
                    fraction: min(1, m.loopPersistence / 1.5),
                    caption: ruminationCaption(m),
                    badge: m.ruminationSignificant ? "verified" : nil
                )

                MetricCard(
                    icon: "circle.hexagongrid",
                    title: "Exploration",
                    accent: teal,
                    value: percentLabel(m.flareIndex),
                    fraction: m.flareIndex,
                    caption: explorationCaption(m),
                    badge: nil
                )

                MetricCard(
                    icon: "arrow.up.forward",
                    title: "Distance from difficult moments",
                    accent: Color(red: 0.4, green: 0.8, blue: 0.55),
                    value: recoveryLabel(m),
                    fraction: recoveryFraction(m),
                    caption: recoveryCaption(m),
                    badge: nil
                )

                disclaimer
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private func summary(_ m: TrajectoryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline(m))
                .font(.title3).fontWeight(.semibold)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(m.pointCount) entries · last 30 days")
                .font(.caption).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var disclaimer: some View {
        Text("These are reflective patterns from your writing — not a diagnosis or a measure of clinical recovery.")
            .font(.caption2)
            .foregroundColor(.gray.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.white)
            Text("Analysing your trajectory…")
                .font(.subheadline).foregroundColor(.gray)
        }
    }

    // MARK: - Plain-language interpretation

    private func headline(_ m: TrajectoryMetrics) -> String {
        if m.ruminationSignificant {
            return "You've been circling similar themes lately."
        }
        if m.recoveryVelocity > 0.002 {
            return "You've been moving toward lighter ground."
        }
        if m.flareIndex > 0.5 {
            return "You've been exploring a lot of new territory."
        }
        return "Your recent writing has felt fairly steady."
    }

    private func ruminationLevel(_ m: TrajectoryMetrics) -> String {
        switch m.loopPersistence {
        case ..<0.3: return "Low"
        case 0.3..<0.8: return "Moderate"
        default: return "High"
        }
    }

    private func ruminationCaption(_ m: TrajectoryMetrics) -> String {
        m.ruminationSignificant
            ? "Your entries keep returning to the same emotional loop."
            : "No strong recurring loop stands out right now."
    }

    private func explorationCaption(_ m: TrajectoryMetrics) -> String {
        m.flareIndex > 0.5
            ? "You're writing across a wide range of themes."
            : "You're staying close to a few familiar themes."
    }

    private func recoveryLabel(_ m: TrajectoryMetrics) -> String {
        if m.recoveryVelocity > 0.002 { return "Gaining" }
        if m.recoveryVelocity < -0.002 { return "Returning" }
        return "Steady"
    }

    private func recoveryFraction(_ m: TrajectoryMetrics) -> Double {
        // map slope symmetrically around 0 into [0,1] for the gauge
        min(1, max(0, 0.5 + m.recoveryVelocity * 20))
    }

    private func recoveryCaption(_ m: TrajectoryMetrics) -> String {
        if m.recoveryVelocity > 0.002 { return "You're drifting away from your most difficult entries." }
        if m.recoveryVelocity < -0.002 { return "You're circling back toward earlier difficult moments." }
        return "You're holding a steady distance from difficult moments."
    }

    private func percentLabel(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let icon: String
    let title: String
    let accent: Color
    let value: String
    let fraction: Double
    let caption: String
    let badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundColor(accent)
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(accent.opacity(0.15)).clipShape(Capsule())
                }
                Text(value).font(.headline).foregroundColor(accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                    Capsule().fill(accent).frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)

            Text(caption).font(.caption).foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.2), lineWidth: 1))
        )
    }
}
