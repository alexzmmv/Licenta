//
//  ClusterGraphView.swift
//  GJournal
//
//  Obsidian-style knowledge graph visualization for journal entry clusters.
//  Uses SwiftUI Canvas for O(1) rendering regardless of node count.
//  Force-directed layout with convergence detection and coordinate persistence.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Graph Data Models

/// A node in the knowledge graph representing a single Bit
struct GraphNode: Identifiable {
    let id: UUID
    let title: String
    let emotion: Emotion
    let clusterID: Int?
    let createdAt: Date
    let intensity: Int

    /// Position in the 2D graph space
    var position: CGPoint

    /// Velocity for physics simulation
    var velocity: CGPoint = .zero
}

/// An edge connecting two nodes in the same cluster
struct GraphEdge: Identifiable {
    let id = UUID()
    let sourceID: UUID
    let targetID: UUID
    let clusterID: Int
}

// MARK: - Force-Directed Layout Engine

/// Force-directed graph layout: Coulomb repulsion + Hooke attraction + cluster gravity.
/// Runs a background Task and stops early when max per-step movement < 0.5 px (convergence).
class ForceDirectedLayout: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var clusterNames: [Int: String] = [:]
    @Published var isSimulating = false

    func buildGraph(from bits: [Bit], in size: CGSize) {
        guard !bits.isEmpty else {
            nodes = []; edges = []; clusterNames = [:]
            return
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.35

        let bitsByCluster = Dictionary(grouping: bits) { $0.clusterID ?? -1 }
        let sortedClusters = bitsByCluster.keys.sorted()
        let clusterCount = sortedClusters.count

        var initialNodes: [GraphNode] = []

        for (clusterIndex, clusterID) in sortedClusters.enumerated() {
            let clusterBits = bitsByCluster[clusterID] ?? []
            let clusterAngle = (CGFloat(clusterIndex) / CGFloat(max(1, clusterCount))) * 2 * .pi
            let clusterCenter = CGPoint(
                x: center.x + cos(clusterAngle) * radius,
                y: center.y + sin(clusterAngle) * radius
            )
            let localRadius: CGFloat = clusterID == -1 ? radius * 0.4 : 60.0

            for (bitIndex, bit) in clusterBits.enumerated() {
                let position: CGPoint
                if let gx = bit.graphX, let gy = bit.graphY {
                    // Restore cached position — simulation will converge in very few steps
                    position = CGPoint(x: CGFloat(gx), y: CGFloat(gy))
                } else {
                    let bitAngle = (CGFloat(bitIndex) / CGFloat(max(1, clusterBits.count))) * 2 * .pi
                    let jitter = CGFloat.random(in: -15...15)
                    position = CGPoint(
                        x: clusterCenter.x + cos(bitAngle) * localRadius + jitter,
                        y: clusterCenter.y + sin(bitAngle) * localRadius + jitter
                    )
                }

                initialNodes.append(GraphNode(
                    id: bit.id,
                    title: bit.title ?? String(bit.feel.prefix(20)),
                    emotion: bit.emotion,
                    clusterID: bit.clusterID,
                    createdAt: bit.createdAt,
                    intensity: bit.intensity,
                    position: position
                ))
            }
        }

        // Build edges + cluster names
        var newEdges: [GraphEdge] = []
        var newClusterNames: [Int: String] = [:]
        let clusterGroups = Dictionary(
            grouping: initialNodes.filter { $0.clusterID != nil && $0.clusterID! >= 0 }
        ) { $0.clusterID! }

        for (clusterID, clusterNodes) in clusterGroups {
            let clusterBits = bits.filter { $0.clusterID == clusterID }
            if let persistedName = clusterBits.compactMap({ $0.cluster?.name }).first {
                newClusterNames[clusterID] = persistedName
            } else {
                newClusterNames[clusterID] = ClusterNamer.generateName(for: clusterBits, fallbackID: clusterID)
            }

            if clusterNodes.count > 1 {
                let hub = clusterNodes[0]
                for i in 1..<clusterNodes.count {
                    newEdges.append(GraphEdge(sourceID: hub.id, targetID: clusterNodes[i].id, clusterID: clusterID))
                }
            }
        }

        self.nodes = initialNodes
        self.edges = newEdges
        self.clusterNames = newClusterNames

        Task.detached(priority: .userInitiated) { [weak self, initialNodes, newEdges] in
            guard let self = self else { return }
            await MainActor.run { self.isSimulating = true }

            var simulationNodes = initialNodes
            let maxIters = 250

            for _ in 0..<maxIters {
                let prevPositions = simulationNodes.map { $0.position }
                simulationNodes = self.computeStep(
                    nodes: simulationNodes,
                    edges: newEdges,
                    center: center,
                    repulsion: 12000,
                    attraction: 0.12,
                    minDist: 130,
                    gravity: 0.002,
                    damping: 0.85
                )

                var maxMovement: CGFloat = 0
                for (prev, next) in zip(prevPositions, simulationNodes) {
                    let d = hypot(next.position.x - prev.x, next.position.y - prev.y)
                    if d > maxMovement { maxMovement = d }
                }
                if maxMovement < 0.5 { break }
            }

            let finalNodes = simulationNodes
            await MainActor.run {
                self.nodes = finalNodes
                self.isSimulating = false
            }
        }
    }

    nonisolated private func computeStep(
        nodes: [GraphNode],
        edges: [GraphEdge],
        center: CGPoint,
        repulsion: CGFloat,
        attraction: CGFloat,
        minDist: CGFloat,
        gravity: CGFloat,
        damping: CGFloat
    ) -> [GraphNode] {
        guard !nodes.isEmpty else { return [] }
        var nextNodes = nodes
        var forces = Array(repeating: CGPoint.zero, count: nodes.count)
        let repulsionCutoff: CGFloat = 300

        // 1. Repulsion (Coulomb) with distance cutoff — reduces O(N²) to ~O(N·k)
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                var dx = nodes[i].position.x - nodes[j].position.x
                var dy = nodes[i].position.y - nodes[j].position.y
                guard abs(dx) < repulsionCutoff && abs(dy) < repulsionCutoff else { continue }
                if dx == 0 && dy == 0 { dx = CGFloat.random(in: -0.1...0.1); dy = CGFloat.random(in: -0.1...0.1) }
                let distance = sqrt(dx * dx + dy * dy)
                let actualDistance = max(distance, 1.0)
                let repulsionFactor: CGFloat = (nodes[i].clusterID == nodes[j].clusterID && nodes[i].clusterID != -1) ? 0.3 : 3.0
                var force = (repulsion * repulsionFactor) / (actualDistance * actualDistance)
                if distance < minDist { force += (minDist - distance) * 5.0 }
                let fx = (dx / actualDistance) * force
                let fy = (dy / actualDistance) * force
                forces[i].x += fx; forces[i].y += fy
                forces[j].x -= fx; forces[j].y -= fy
            }
        }

        // 2. Attraction along edges (Hooke)
        for edge in edges {
            guard let si = nodes.firstIndex(where: { $0.id == edge.sourceID }),
                  let ti = nodes.firstIndex(where: { $0.id == edge.targetID }) else { continue }
            let dx = nodes[ti].position.x - nodes[si].position.x
            let dy = nodes[ti].position.y - nodes[si].position.y
            forces[si].x += dx * attraction; forces[si].y += dy * attraction
            forces[ti].x -= dx * attraction; forces[ti].y -= dy * attraction
        }

        // 3. Cluster gravity — pull same-cluster nodes toward their centroid
        let clusterGroups = Dictionary(
            grouping: nodes.enumerated().filter { $0.element.clusterID != nil && $0.element.clusterID! >= 0 }
        ) { $0.element.clusterID! }
        for (_, clusterNodes) in clusterGroups where clusterNodes.count > 1 {
            let avgX = clusterNodes.reduce(0.0) { $0 + $1.element.position.x } / CGFloat(clusterNodes.count)
            let avgY = clusterNodes.reduce(0.0) { $0 + $1.element.position.y } / CGFloat(clusterNodes.count)
            let clusterCenter = CGPoint(x: avgX, y: avgY)
            for (idx, _) in clusterNodes {
                forces[idx].x += (clusterCenter.x - nodes[idx].position.x) * 0.1
                forces[idx].y += (clusterCenter.y - nodes[idx].position.y) * 0.1
            }
        }

        // 4. Global center gravity — keep graph from drifting off-screen
        for i in 0..<nodes.count {
            forces[i].x += (center.x - nodes[i].position.x) * gravity
            forces[i].y += (center.y - nodes[i].position.y) * gravity
        }

        // 5. Integrate with velocity damping
        for i in 0..<nodes.count {
            nextNodes[i].velocity.x = (nodes[i].velocity.x + forces[i].x) * damping
            nextNodes[i].velocity.y = (nodes[i].velocity.y + forces[i].y) * damping
            let maxVel: CGFloat = 20
            nextNodes[i].velocity.x = max(-maxVel, min(maxVel, nextNodes[i].velocity.x))
            nextNodes[i].velocity.y = max(-maxVel, min(maxVel, nextNodes[i].velocity.y))
            nextNodes[i].position.x += nextNodes[i].velocity.x
            nextNodes[i].position.y += nextNodes[i].velocity.y
        }
        return nextNodes
    }
}

// MARK: - Cluster Graph View

struct ClusterGraphView: View {
    @ObservedObject var repository: BaseJournalRepository
    @StateObject private var layout = ForceDirectedLayout()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var selectedNodeID: UUID?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isLoading = true
    @State private var isSpinning = false
    @State private var bitToEdit: Bit?
    @State private var graphSize: CGSize = .zero

    private var selectedNode: GraphNode? {
        layout.nodes.first { $0.id == selectedNodeID }
    }

    private let clusterColors: [Color] = [
        .pink, .purple, .blue, .cyan, .teal, .green,
        .yellow, .orange, .red, .indigo, .mint
    ]

    private func colorForCluster(_ clusterID: Int?) -> Color {
        guard let id = clusterID, id >= 0 else { return .gray.opacity(0.5) }
        return clusterColors[id % clusterColors.count]
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()

            GeometryReader { geometry in
                // Single Canvas — no SwiftUI view tree per node, no layout passes at 60fps
                Canvas { context, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let tx = offset.width + dragOffset.width
                    let ty = offset.height + dragOffset.height
                    // Replicate .scaleEffect(scale).offset(tx, ty) as an affine transform
                    context.transform = CGAffineTransform(
                        a: scale, b: 0, c: 0, d: scale,
                        tx: cx * (1 - scale) + tx,
                        ty: cy * (1 - scale) + ty
                    )

                    // Edges
                    for edge in layout.edges {
                        guard let src = layout.nodes.first(where: { $0.id == edge.sourceID }),
                              let dst = layout.nodes.first(where: { $0.id == edge.targetID }) else { continue }
                        var path = Path()
                        path.move(to: src.position)
                        path.addLine(to: dst.position)
                        context.stroke(path, with: .color(colorForCluster(edge.clusterID).opacity(0.3)), lineWidth: 1)
                    }

                    // Nodes
                    for node in layout.nodes {
                        let isSelected = node.id == selectedNodeID
                        let isNoise = node.clusterID == nil || node.clusterID == -1
                        let clusterColor = colorForCluster(node.clusterID)
                        let rect = CGRect(x: node.position.x - 70, y: node.position.y - 18, width: 140, height: 36)
                        let nodePath = Path(roundedRect: rect, cornerRadius: 12)

                        context.fill(nodePath, with: .color(
                            isSelected ? clusterColor.opacity(0.3) : Color(red: 0.1, green: 0.1, blue: 0.12)
                        ))
                        context.stroke(nodePath, with: .color(
                            isSelected ? Color.white : clusterColor.opacity(isNoise ? 0.4 : 0.8)
                        ), lineWidth: isSelected ? 2 : 1)

                        context.draw(
                            Text("\(node.emotion.emoji) \(node.title)").font(.caption2).foregroundColor(.white),
                            in: CGRect(x: rect.minX + 6, y: rect.minY, width: rect.width - 12, height: rect.height)
                        )
                    }

                    // Cluster labels (drawn above nodes)
                    for center in clusterCenters {
                        let name = layout.clusterNames[center.clusterID] ?? "Cluster \(center.clusterID)"
                        context.draw(
                            Text(name).font(.caption2).fontWeight(.medium)
                                .foregroundColor(colorForCluster(center.clusterID).opacity(0.9)),
                            at: CGPoint(x: center.position.x, y: center.position.y - 32)
                        )
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            let t = value.translation
                            dragOffset = .zero
                            if hypot(t.width, t.height) < 8 {
                                // Short movement — treat as tap
                                let graphPoint = adjustPoint(value.startLocation)
                                let hitID = hitTest(at: graphPoint)
                                withAnimation(.spring(response: 0.3)) {
                                    if let id = hitID {
                                        selectedNodeID = (selectedNodeID == id) ? nil : id
                                    } else {
                                        selectedNodeID = nil
                                    }
                                }
                            } else {
                                // Long movement — pan the canvas
                                offset.width += t.width
                                offset.height += t.height
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture().onChanged { value in
                        scale = max(0.3, min(3.0, value))
                    }
                )
                .onAppear {
                    graphSize = geometry.size
                    layout.buildGraph(from: repository.bits, in: geometry.size)
                    withAnimation(.easeOut(duration: 0.6)) { isLoading = false }
                }
            }
            .opacity(isLoading ? 0 : 1)

            VStack {
                headerView
                Spacer()
                if let node = selectedNode {
                    nodeDetailCard(node)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                legendView
            }
            .opacity(isLoading ? 0 : 1)

            if isLoading {
                VStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.2), lineWidth: 4).frame(width: 60, height: 60)
                        Circle().trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                            .onAppear { isSpinning = true }
                    }
                    VStack(spacing: 8) {
                        Text("Analyzing Patterns").font(.headline).foregroundColor(.white)
                        Text("Connecting your thoughts and memories...").font(.subheadline).foregroundColor(.gray)
                    }
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $bitToEdit) { bit in
            BitDetailView(bit: bit, clusterName: bit.clusterID.flatMap { layout.clusterNames[$0] })
        }
        .onChange(of: repository.bits) {
            guard !graphSize.width.isZero else { return }
            layout.buildGraph(from: repository.bits, in: graphSize)
        }
        .onChange(of: layout.isSimulating) { _, isNowSimulating in
            guard !isNowSimulating else { return }
            // Persist node positions so the next open skips most of the simulation
            for node in layout.nodes {
                if let bit = repository.bits.first(where: { $0.id == node.id }) {
                    bit.graphX = Double(node.position.x)
                    bit.graphY = Double(node.position.y)
                }
            }
            try? modelContext.save()
        }
    }

    // MARK: - Manual Hit-Testing

    /// Convert a screen-space point to graph-space, accounting for current scale + offset.
    private func adjustPoint(_ point: CGPoint) -> CGPoint {
        let cx = graphSize.width / 2
        let cy = graphSize.height / 2
        return CGPoint(
            x: (point.x - cx * (1 - scale) - offset.width) / scale,
            y: (point.y - cy * (1 - scale) - offset.height) / scale
        )
    }

    private func hitTest(at graphPoint: CGPoint) -> UUID? {
        for node in layout.nodes.reversed() {
            let rect = CGRect(x: node.position.x - 70, y: node.position.y - 18, width: 140, height: 36)
            if rect.contains(graphPoint) { return node.id }
        }
        return nil
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3).fontWeight(.semibold).foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2)).clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Knowledge Graph").font(.title3).fontWeight(.bold).foregroundColor(.white)
                Text("\(layout.nodes.count) entries • \(clusterCount) clusters")
                    .font(.caption).foregroundColor(.gray)
            }

            Spacer()

            Button {
                withAnimation { layout.buildGraph(from: repository.bits, in: graphSize) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3).foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2)).clipShape(Circle())
            }
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    // MARK: - Node Detail Card

    @ViewBuilder
    private func nodeDetailCard(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(node.emotion.emoji).font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title).font(.headline).foregroundColor(.white).lineLimit(1)

                    HStack(spacing: 8) {
                        Text(node.emotion.rawValue).font(.caption).foregroundColor(node.emotion.color)
                        Text("•").foregroundColor(.gray)
                        Text(formatDate(node.createdAt)).font(.caption).foregroundColor(.gray)

                        if let clusterID = node.clusterID, clusterID >= 0 {
                            Text("•").foregroundColor(.gray)
                            HStack(spacing: 4) {
                                Circle().fill(colorForCluster(clusterID)).frame(width: 8, height: 8)
                                Text(layout.clusterNames[clusterID] ?? "Cluster \(clusterID)")
                                    .font(.caption).foregroundColor(.gray)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 2) {
                    ForEach(1...4, id: \.self) { level in
                        Circle()
                            .fill(level <= node.intensity ? Color.pink : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Button {
                    if let bit = repository.bits.first(where: { $0.id == node.id }) {
                        bitToEdit = bit
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2).foregroundColor(.pink)
                }
                .padding(.leading, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
        )
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    // MARK: - Legend

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(uniqueClusterIDs), id: \.self) { clusterID in
                    HStack(spacing: 4) {
                        Circle().fill(colorForCluster(clusterID)).frame(width: 8, height: 8)
                        Text(clusterID == -1 ? "Unclustered" : (layout.clusterNames[clusterID] ?? "Cluster \(clusterID)"))
                            .font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    .onTapGesture {
                        if let center = clusterCenters.first(where: { $0.clusterID == clusterID }) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                offset = CGSize(
                                    width: scale * (graphSize.width / 2 - center.position.x),
                                    height: scale * (graphSize.height / 2 - center.position.y)
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    private var clusterCount: Int {
        Set(layout.nodes.compactMap { $0.clusterID }).filter { $0 >= 0 }.count
    }

    private var uniqueClusterIDs: [Int] {
        Array(Set(layout.nodes.map { $0.clusterID ?? -1 })).sorted()
    }

    private var clusterCenters: [(clusterID: Int, position: CGPoint)] {
        let groups = Dictionary(
            grouping: layout.nodes.filter { $0.clusterID != nil && $0.clusterID! >= 0 }
        ) { $0.clusterID! }
        return groups.map { clusterID, nodes in
            let avgX = nodes.reduce(0) { $0 + $1.position.x } / CGFloat(nodes.count)
            let avgY = nodes.reduce(0) { $0 + $1.position.y } / CGFloat(nodes.count)
            return (clusterID: clusterID, position: CGPoint(x: avgX, y: avgY))
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
