import SwiftUI

struct NetworkGraphView: View {
    @Environment(\.dismiss) private var dismiss
    let network: PsychologicalNetwork

    private let emotions   = Emotion.allCases
    private let nodeRadius: CGFloat = 28

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { geo in
                    networkCanvas(size: geo.size)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Psychological Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(tierLabel)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - Graph Canvas

    @ViewBuilder
    private func networkCanvas(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ringRadius = min(size.width, size.height) / 2 - nodeRadius - 40
        let positions = ringPositions(center: center, radius: ringRadius)

        ZStack {
            // Edge layer (Canvas for performance)
            Canvas { ctx, _ in
                for edge in network.edges {
                    guard
                        let i = emotions.firstIndex(of: edge.first),
                        let j = emotions.firstIndex(of: edge.second)
                    else { continue }

                    let from = positions[i]
                    let to   = positions[j]
                    let lw   = CGFloat(max(0.8, min(5.0, edge.absWeight * 9)))
                    let col  = edge.isPositive
                        ? Color(red: 0.45, green: 0.35, blue: 1.0)   // purple-blue
                        : Color(red: 1.0, green: 0.28, blue: 0.28)   // red

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    ctx.stroke(path, with: .color(col.opacity(0.75)), lineWidth: lw)
                }
            }
            .frame(width: size.width, height: size.height)

            // Node layer
            ForEach(Array(emotions.enumerated()), id: \.offset) { i, emotion in
                emotionNode(emotion: emotion, position: positions[i])
            }

            // Legend (bottom-center)
            legend
                .position(x: size.width / 2, y: size.height - 24)
        }
    }

    // MARK: - Node

    private func emotionNode(emotion: Emotion, position: CGPoint) -> some View {
        let centrality    = network.centrality[emotion] ?? 0
        let maxCentrality = network.centrality.values.max() ?? 1
        let scale         = maxCentrality > 0 ? (0.75 + 0.5 * CGFloat(centrality / maxCentrality)) : 1.0

        return VStack(spacing: 2) {
            Text(emotion.emoji)
                .font(.system(size: 14))
            Text(emotion.rawValue)
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: nodeRadius * 2 * scale, height: nodeRadius * 2 * scale)
        .background(
            Circle()
                .fill(emotion.color.opacity(0.85))
                .shadow(color: emotion.color.opacity(0.5), radius: 6)
        )
        .position(position)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.45, green: 0.35, blue: 1.0))
                    .frame(width: 20, height: 2.5)
                Text("positive")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 1.0, green: 0.28, blue: 0.28))
                    .frame(width: 20, height: 2.5)
                Text("negative")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Text("n=\(network.n)")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func ringPositions(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        let count = Double(emotions.count)
        return emotions.indices.map { i in
            let angle = Double(i) / count * 2 * .pi - .pi / 2
            return CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
        }
    }

    private var tierLabel: String {
        switch network.tier {
        case .spearman:   return "Spearman"
        case .ledoitWolf: return "Ledoit-Wolf"
        }
    }
}

// MARK: - Empty-state view while computing

struct NetworkGraphLoadingView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Building network…")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Psychological Network")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
