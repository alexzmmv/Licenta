import SwiftUI

struct NetworkGraphView: View {
    @Environment(\.dismiss) private var dismiss
    let network: PsychologicalNetwork

    @State private var selectedNode: NetworkVariable? = nil
    @State private var selectedEdge: PsychNetworkEdge? = nil

    private let nodeRadius: CGFloat = 28
    private let tagColor = Color(red: 0.35, green: 0.75, blue: 0.55)

    /// Nodes that actually participate in an edge, largest hub first.
    private var nodes: [NetworkVariable] {
        network.centrality.keys.sorted {
            (network.centrality[$0] ?? 0) > (network.centrality[$1] ?? 0)
        }
    }

    // MARK: - VoiceOver

    /// Plain-language summary of the whole network, read first to VoiceOver users
    /// since the Canvas-drawn edges cannot be traversed by assistive technology.
    private var accessibilitySummary: String {
        guard let hub = nodes.first else {
            return String(localized: "No strong connections in your psychological network yet. Keep journaling to reveal stable patterns.")
        }
        let nodeCount = nodes.count
        let edgeCount = network.edges.count
        var parts: [String] = []
        parts.append(String(localized: "Psychological network based on \(network.n) entries."))
        parts.append(String(localized: "\(nodeCount) connected variables and \(edgeCount) connections."))
        parts.append(String(localized: "The most central variable is \(hub.label)."))
        if let strongest = network.edges.max(by: { $0.absWeight < $1.absWeight }) {
            let kind = strongest.isPositive
                ? String(localized: "reinforcing")
                : String(localized: "buffering")
            let r = strongest.weight.formatted(.number.precision(.fractionLength(2)))
            parts.append(String(localized: "The strongest link is a \(kind) connection between \(strongest.first.label) and \(strongest.second.label), correlation \(r)."))
        }
        return parts.joined(separator: " ")
    }

    /// Spoken description for a single node, including its neighbours.
    private func nodeAccessibilityLabel(_ variable: NetworkVariable) -> String {
        let kind = variable.isEmotion
            ? String(localized: "emotion")
            : String(localized: "behavioral tag")
        let centrality = (network.centrality[variable] ?? 0).formatted(.number.precision(.fractionLength(2)))
        let neighbors = network.edges.compactMap { edge -> String? in
            if edge.first == variable { return edge.second.label }
            if edge.second == variable { return edge.first.label }
            return nil
        }
        var label = String(localized: "\(variable.label), \(kind). Centrality \(centrality).")
        if !neighbors.isEmpty {
            label += " " + String(localized: "Connected to \(neighbors.joined(separator: ", ")).")
        }
        return label
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if nodes.isEmpty {
                        emptyState
                            .frame(maxHeight: .infinity)
                    } else {
                        GeometryReader { geo in
                            networkCanvas(size: geo.size)
                        }
                        .padding(.top, 8)
                        
                        detailCardView
                    }
                }
            }
            .navigationTitle("Psychological Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
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
                    
                    var op: Double = 0.75
                    var extraLineWidth: CGFloat = 0.0
                    
                    if let selNode = selectedNode {
                        let isConnected = (edge.first == selNode || edge.second == selNode)
                        op = isConnected ? 0.85 : 0.05
                    } else if let selEdge = selectedEdge {
                        let isSelected = (edge.first == selEdge.first && edge.second == selEdge.second) ||
                                         (edge.first == selEdge.second && edge.second == selEdge.first)
                        op = isSelected ? 1.0 : 0.05
                        if isSelected {
                            extraLineWidth = 1.5
                        }
                    }
                    
                    let lw = CGFloat(max(0.8, min(5.0, edge.absWeight * 9))) + extraLineWidth
                    let col = edge.isPositive
                        ? Color(red: 0.45, green: 0.35, blue: 1.0)
                        : Color(red: 1.0, green: 0.28, blue: 0.28)
                    var path = Path()
                    path.move(to: positions[i])
                    path.addLine(to: positions[j])
                    ctx.stroke(path, with: .color(col.opacity(op)), lineWidth: lw)
                }
            }
            .frame(width: size.width, height: size.height)
            // Canvas-drawn edges aren't individually traversable, so the Canvas itself
            // becomes the summary element — first in traversal order and reachable by
            // touch exploration, describing the whole graph in words.
            .accessibilityElement()
            .accessibilityLabel(Text("Network overview"))
            .accessibilityValue(Text(accessibilitySummary))
            .accessibilityAddTraits(.isSummaryElement)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let tapPoint = value.location
                        
                        var bestEdge: PsychNetworkEdge? = nil
                        var minDistance: CGFloat = 999
                        
                        for edge in network.edges {
                            guard let i = indexOf[edge.first], let j = indexOf[edge.second] else { continue }
                            let posA = positions[i]
                            let posB = positions[j]
                            let dist = distanceToSegment(p: tapPoint, a: posA, b: posB)
                            if dist < 14.0 && dist < minDistance {
                                minDistance = dist
                                bestEdge = edge
                            }
                        }
                        
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if let edge = bestEdge {
                                selectedEdge = edge
                                selectedNode = nil
                            } else {
                                selectedEdge = nil
                                selectedNode = nil
                            }
                        }
                    }
            )

            ForEach(Array(nodes.enumerated()), id: \.offset) { i, variable in
                node(variable, position: positions[i])
            }

            legend.position(x: size.width / 2, y: size.height - 24)
        }
    }

    // MARK: - Node

    private func node(_ variable: NetworkVariable, position: CGPoint) -> some View {
        let centrality = network.centrality[variable] ?? 0
        let maxCentrality = network.centrality.values.max() ?? 1
        var scale = maxCentrality > 0 ? (0.8 + 0.5 * CGFloat(centrality / maxCentrality)) : 1.0
        
        var op: Double = 1.0
        var isSelected = false
        
        if let selNode = selectedNode {
            if selNode == variable {
                scale *= 1.15
                isSelected = true
            } else {
                let isNeighbor = network.edges.contains { edge in
                    (edge.first == selNode && edge.second == variable) ||
                    (edge.second == selNode && edge.first == variable)
                }
                op = isNeighbor ? 1.0 : 0.15
            }
        } else if let selEdge = selectedEdge {
            let isConnected = (selEdge.first == variable || selEdge.second == variable)
            op = isConnected ? 1.0 : 0.15
            if isConnected {
                scale *= 1.1
            }
        }

        return nodeShape(variable, scale: scale, isSelected: isSelected)
            .opacity(op)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .position(position)
            .onTapGesture {
                selectNode(variable)
            }
            .accessibilityElement()
            .accessibilityLabel(Text(nodeAccessibilityLabel(variable)))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Double tap to focus this variable's connections"))
    }

    /// The purely visual node glyph, split out so the modifier chain in `node(_:position:)`
    /// stays short enough for the Swift type-checker.
    @ViewBuilder
    private func nodeShape(_ variable: NetworkVariable, scale: CGFloat, isSelected: Bool) -> some View {
        switch variable {
        case .emotion(let e):
            VStack(spacing: 2) {
                Text(e.emoji).font(.system(size: 14))
                Text(e.rawValue).font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.white).lineLimit(1)
            }
            .frame(width: nodeRadius * 2 * scale, height: nodeRadius * 2 * scale)
            .background(
                Circle()
                    .fill(e.color.opacity(0.85))
                    .shadow(color: e.color.opacity(0.5), radius: 6)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                            .shadow(color: .white.opacity(isSelected ? 0.6 : 0), radius: 4)
                    )
            )
        case .tag(let lemma, _):
            Text(lemma.capitalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(width: nodeRadius * 2 * scale, height: nodeRadius * 1.5 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tagColor.opacity(0.85))
                        .shadow(color: tagColor.opacity(0.5), radius: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                                .shadow(color: .white.opacity(isSelected ? 0.6 : 0), radius: 4)
                        )
                )
        }
    }

    private func selectNode(_ variable: NetworkVariable) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if selectedNode == variable {
                selectedNode = nil
            } else {
                selectedNode = variable
                selectedEdge = nil
            }
        }
    }

    // MARK: - Geometry / Proximity Math Helpers

    private func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let l2 = distanceSquared(a, b)
        if l2 == 0 { return distance(p, a) }
        var t = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2
        t = max(0, min(1, t))
        let projection = CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
        return distance(p, projection)
    }

    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return sqrt(distanceSquared(a, b))
    }

    private var detailCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let node = selectedNode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            if case .emotion(let e) = node {
                                Circle().fill(e.color.opacity(0.2)).frame(width: 32, height: 32)
                                Text(e.emoji).font(.subheadline)
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(tagColor.opacity(0.2)).frame(width: 32, height: 32)
                                Image(systemName: "tag.fill").font(.caption).foregroundColor(tagColor)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.label)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(node.isEmotion ? "Emotion Variable" : "Behavioral Tag")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        let centrality = network.centrality[node] ?? 0
                        Text(String(format: "Centrality: %.2f", centrality))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                    }
                    
                    Text("This variable has an expected influence of \(String(format: "%.2f", network.centrality[node] ?? 0)) on your network. A higher centrality score indicates this emotion or behavior plays a key role in triggering or buffering other variables.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineSpacing(3)
                }
            } else if let edge = selectedEdge {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(edge.first.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        
                        Text(edge.second.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        let sign = edge.weight > 0 ? "+" : ""
                        Text(String(format: "r = \(sign)%.2f", edge.weight))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(edge.weight > 0 ? Color(red: 0.55, green: 0.45, blue: 1.0) : Color(red: 1.0, green: 0.35, blue: 0.35))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background((edge.weight > 0 ? Color(red: 0.55, green: 0.45, blue: 1.0) : Color(red: 1.0, green: 0.35, blue: 0.35)).opacity(0.12))
                            .cornerRadius(8)
                    }
                    
                    if edge.weight > 0 {
                        Text("**Trigger Pathway:** When **\(edge.first.label)** increases, **\(edge.second.label)** tends to rise as well. This coupling suggests they reinforce each other directly in your coping patterns.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineSpacing(3)
                    } else {
                        Text("**Buffer Pathway:** When **\(edge.first.label)** is present, **\(edge.second.label)** tends to be suppressed. This suggests one acts as a protective buffer or compensation mechanism for the other.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineSpacing(3)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                    Text("Tap any node or edge connection line to analyze emotional triggers, feedback loops, and buffers in your psychological network.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineSpacing(3)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedNode == nil && selectedEdge == nil)
        .accessibilityElement(children: .combine)
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
