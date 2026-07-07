import SwiftUI

struct NetworkGraphView: View {
    @Environment(\.dismiss) private var dismiss
    let network: PsychologicalNetwork

    private let nodeRadius: CGFloat = 28
    private let tagColor = Color(red: 0.35, green: 0.75, blue: 0.55)

    /// Nodes that actually participate in an edge, largest hub first.
    private var nodes: [NetworkVariable] {
        network.centrality.keys.sorted {
            (network.centrality[$0] ?? 0) > (network.centrality[$1] ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if nodes.isEmpty {
                    emptyState
                } else {
                    GeometryReader { geo in networkCanvas(size: geo.size) }
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Psychological Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(tierLabel).font(.caption2).foregroundColor(.gray)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.largeTitle).foregroundColor(.gray)
            Text("No strong connections yet")
                .font(.subheadline).foregroundColor(.gray)
            Text("Keep journaling — the network fills in as stable patterns emerge.")
                .font(.caption).foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }

    // MARK: - Graph Canvas

    @ViewBuilder
    private func networkCanvas(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ringRadius = min(size.width, size.height) / 2 - nodeRadius - 44
        let positions = ringPositions(count: nodes.count, center: center, radius: ringRadius)
        let indexOf = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1, $0) })

        ZStack {
            Canvas { ctx, _ in
                for edge in network.edges {
                    guard let i = indexOf[edge.first], let j = indexOf[edge.second] else { continue }
                    let lw = CGFloat(max(0.8, min(5.0, edge.absWeight * 9)))
                    let col = edge.isPositive
                        ? Color(red: 0.45, green: 0.35, blue: 1.0)
                        : Color(red: 1.0, green: 0.28, blue: 0.28)
                    var path = Path()
                    path.move(to: positions[i])
                    path.addLine(to: positions[j])
                    ctx.stroke(path, with: .color(col.opacity(0.75)), lineWidth: lw)
                }
            }
            .frame(width: size.width, height: size.height)

            ForEach(Array(nodes.enumerated()), id: \.offset) { i, variable in
                node(variable, position: positions[i])
            }

            legend.position(x: size.width / 2, y: size.height - 24)
        }
    }

    // MARK: - Node

    @ViewBuilder
    private func node(_ variable: NetworkVariable, position: CGPoint) -> some View {
        let centrality = network.centrality[variable] ?? 0
        let maxCentrality = network.centrality.values.max() ?? 1
        let scale = maxCentrality > 0 ? (0.8 + 0.5 * CGFloat(centrality / maxCentrality)) : 1.0

        switch variable {
        case .emotion(let e):
            VStack(spacing: 2) {
                Text(e.emoji).font(.system(size: 14))
                Text(e.rawValue).font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.white).lineLimit(1)
            }
            .frame(width: nodeRadius * 2 * scale, height: nodeRadius * 2 * scale)
            .background(Circle().fill(e.color.opacity(0.85)).shadow(color: e.color.opacity(0.5), radius: 6))
            .position(position)
        case .tag(let lemma, _):
            Text(lemma.capitalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(width: nodeRadius * 2 * scale, height: nodeRadius * 1.5 * scale)
                .background(RoundedRectangle(cornerRadius: 8).fill(tagColor.opacity(0.85))
                    .shadow(color: tagColor.opacity(0.5), radius: 6))
                .position(position)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Color(red: 0.45, green: 0.35, blue: 1.0), text: "positive")
            legendItem(color: Color(red: 1.0, green: 0.28, blue: 0.28), text: "negative")
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(tagColor).frame(width: 10, height: 10)
                Text("behavior").font(.caption2).foregroundColor(.gray)
            }
            Text("n=\(network.n)").font(.caption2).foregroundColor(.gray.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.white.opacity(0.05)).clipShape(Capsule())
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 20, height: 2.5)
            Text(text).font(.caption2).foregroundColor(.gray)
        }
    }

    // MARK: - Helpers

    private func ringPositions(count: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                           y: center.y + radius * CGFloat(sin(angle)))
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
                    ProgressView().tint(.white)
                    Text("Building network…").font(.subheadline).foregroundColor(.gray)
                }
            }
            .navigationTitle("Psychological Network")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
