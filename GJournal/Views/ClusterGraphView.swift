//
//  ClusterGraphView.swift
//  GJournal
//
//  Obsidian-style knowledge graph visualization for journal entry clusters.
//  Displays bits as nodes and clusters as groups, with force-directed layout.
//  Uses SwiftUI Canvas for performant 2D rendering.
//

import SwiftUI
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

/// Simple force-directed graph layout using Coulomb's law + Hooke's law
class ForceDirectedLayout: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var clusterNames: [Int: String] = [:]
    @Published var isSimulating = false

    // Physics parameters
    private let repulsionStrength: CGFloat = 8000
    private let attractionStrength: CGFloat = 0.08
    private let centerGravity: CGFloat = 0.005
    private let damping: CGFloat = 0.80
    private let minDistance: CGFloat = 100

    private var timer: Timer?
    private var iterationCount = 0
    private let maxIterations = 200

    func buildGraph(from bits: [Bit], in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.35

        // Group bits by cluster to position clusters separately in a larger circle
        let bitsByCluster = Dictionary(grouping: bits) { $0.clusterID ?? -1 }
        let sortedClusters = bitsByCluster.keys.sorted()
        let clusterCount = sortedClusters.count
        
        var initialNodes: [GraphNode] = []
        
        for (clusterIndex, clusterID) in sortedClusters.enumerated() {
            let clusterBits = bitsByCluster[clusterID] ?? []
            
            // Calculate a dedicated center for this cluster
            let clusterAngle = (CGFloat(clusterIndex) / CGFloat(max(1, clusterCount))) * 2 * .pi
            let clusterCenter = CGPoint(
                x: center.x + cos(clusterAngle) * radius,
                y: center.y + sin(clusterAngle) * radius
            )
            
            // Local spread within the cluster
            let localRadius: CGFloat = clusterID == -1 ? radius * 0.4 : 60.0
            
            for (bitIndex, bit) in clusterBits.enumerated() {
                let bitAngle = (CGFloat(bitIndex) / CGFloat(max(1, clusterBits.count))) * 2 * .pi
                let jitter = CGFloat.random(in: -15...15)
                
                let position = CGPoint(
                    x: clusterCenter.x + cos(bitAngle) * localRadius + jitter,
                    y: clusterCenter.y + sin(bitAngle) * localRadius + jitter
                )
                
                initialNodes.append(GraphNode(
                    id: bit.id,
                    title: bit.title ?? bit.feel.prefix(20).description,
                    emotion: bit.feelEmotion,
                    clusterID: bit.clusterID,
                    createdAt: bit.createdAt,
                    intensity: bit.intensity,
                    position: position
                ))
            }
        }

        // Create edges and compute cluster names
        var newEdges: [GraphEdge] = []
        var newClusterNames: [Int: String] = [:]
        let clusterGroups = Dictionary(grouping: initialNodes.filter { $0.clusterID != nil && $0.clusterID != -1 }) { $0.clusterID! }

        for (clusterID, clusterNodes) in clusterGroups {
            // NLP Cluster Naming (prefer persisted name from DB)
            let clusterBits = bits.filter { $0.clusterID == clusterID }
            if let persistedName = clusterBits.compactMap({ $0.cluster?.name }).first {
                newClusterNames[clusterID] = persistedName
            } else {
                newClusterNames[clusterID] = ClusterNamer.generateName(for: clusterBits, fallbackID: clusterID)
            }
            
            // Connect nodes using a hub-and-spoke model (O(N) links)
            if clusterNodes.count > 1 {
                let hub = clusterNodes[0]
                for i in 1..<clusterNodes.count {
                    newEdges.append(GraphEdge(
                        sourceID: hub.id,
                        targetID: clusterNodes[i].id,
                        clusterID: clusterID
                    ))
                }
            }
        }

        self.nodes = initialNodes
        self.edges = newEdges
        self.clusterNames = newClusterNames

        // Run heavy physics simulation in the background
        Task.detached(priority: .userInitiated) { [weak self, initialNodes, newEdges] in
            guard let self = self else { return }
            
            await MainActor.run { self.isSimulating = true }
            
            var simulationNodes = initialNodes
            
            // Extract parameters
            let maxIters = 250 
            let repulsion: CGFloat = 12000 // Higher repulsion for better cluster separation
            let attraction: CGFloat = 0.12  // Stronger internal attraction
            let minDist: CGFloat = 130      // More padding between nodes
            let gravity: CGFloat = 0.002    // Weak center gravity to allow spread
            let damp: CGFloat = 0.85

            for _ in 0..<maxIters {
                simulationNodes = self.computeStep(
                    nodes: simulationNodes,
                    edges: newEdges,
                    center: center,
                    repulsion: repulsion,
                    attraction: attraction,
                    minDist: minDist,
                    gravity: gravity,
                    damping: damp
                )
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

        // 1. Repulsion (Global separation)
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                var dx = nodes[i].position.x - nodes[j].position.x
                var dy = nodes[i].position.y - nodes[j].position.y
                if dx == 0 && dy == 0 {
                    dx = CGFloat.random(in: -0.1...0.1)
                    dy = CGFloat.random(in: -0.1...0.1)
                }
                let distance = sqrt(dx * dx + dy * dy)
                let actualDistance = max(distance, 1.0)
                
                // Push nodes in different clusters apart significantly more than same-cluster nodes
                let repulsionFactor: CGFloat = (nodes[i].clusterID == nodes[j].clusterID && nodes[i].clusterID != -1) ? 0.3 : 3.0
                var force = (repulsion * repulsionFactor) / (actualDistance * actualDistance)
                
                if distance < minDist {
                    force += (minDist - distance) * 5.0
                }
                let fx = (dx / actualDistance) * force
                let fy = (dy / actualDistance) * force
                forces[i].x += fx
                forces[i].y += fy
                forces[j].x -= fx
                forces[j].y -= fy
            }
        }

        // 2. Attraction along edges (Hooke's law)
        for edge in edges {
            guard let sourceIdx = nodes.firstIndex(where: { $0.id == edge.sourceID }),
                  let targetIdx = nodes.firstIndex(where: { $0.id == edge.targetID }) else { continue }
            let dx = nodes[targetIdx].position.x - nodes[sourceIdx].position.x
            let dy = nodes[targetIdx].position.y - nodes[sourceIdx].position.y
            forces[sourceIdx].x += dx * attraction
            forces[sourceIdx].y += dy * attraction
            forces[targetIdx].x -= dx * attraction
            forces[targetIdx].y -= dy * attraction
        }
        
        // 3. Cluster Gravity (Pull nodes in the same cluster toward their collective center)
        let clusterGroups = Dictionary(grouping: nodes.enumerated().filter { $0.element.clusterID != nil && $0.element.clusterID! >= 0 }) { $0.element.clusterID! }
        for (_, clusterNodes) in clusterGroups {
            if clusterNodes.count > 1 {
                let avgX = clusterNodes.reduce(0.0) { $0 + $1.element.position.x } / CGFloat(clusterNodes.count)
                let avgY = clusterNodes.reduce(0.0) { $0 + $1.element.position.y } / CGFloat(clusterNodes.count)
                let clusterCenter = CGPoint(x: avgX, y: avgY)
                
                for (idx, _) in clusterNodes {
                    let dx = clusterCenter.x - nodes[idx].position.x
                    let dy = clusterCenter.y - nodes[idx].position.y
                    forces[idx].x += dx * 0.1 // Cluster attraction factor
                    forces[idx].y += dy * 0.1
                }
            }
        }

        // 4. Global Center Gravity
        for i in 0..<nodes.count {
            let dx = center.x - nodes[i].position.x
            let dy = center.y - nodes[i].position.y
            forces[i].x += dx * gravity
            forces[i].y += dy * gravity
        }

        // 5. Update positions with damping
        for i in 0..<nodes.count {
            nextNodes[i].velocity.x = (nodes[i].velocity.x + forces[i].x) * damping
            nextNodes[i].velocity.y = (nodes[i].velocity.y + forces[i].y) * damping
            let maxVel: CGFloat = 20 // Slightly increased max velocity for faster convergence
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
    @State private var selectedNode: GraphNode?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isLoading = true
    @State private var isSpinning = false
    @State private var bitToEdit: Bit?
    @Environment(\.dismiss) var dismiss

    /// Map cluster IDs to colors
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
            // Dark background
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        selectedNode = nil
                    }
                }

            // Graph canvas
            GeometryReader { geometry in
                ZStack {
                    // Static gesture container - captures touch across the entire screen
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedNode = nil
                            }
                        }
                    
                    // Moving graph content
                    ZStack {
                        // Edges
                        ForEach(layout.edges) { edge in
                            if let source = layout.nodes.first(where: { $0.id == edge.sourceID }),
                               let target = layout.nodes.first(where: { $0.id == edge.targetID }) {
                                Path { path in
                                    path.move(to: source.position)
                                    path.addLine(to: target.position)
                                }
                                .stroke(
                                    colorForCluster(edge.clusterID).opacity(0.3),
                                    lineWidth: 1
                                )
                            }
                        }

                        // Nodes
                        ForEach(layout.nodes) { node in
                            nodeView(node)
                                .position(node.position)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        if selectedNode?.id == node.id {
                                            selectedNode = nil
                                        } else {
                                            selectedNode = node
                                        }
                                    }
                                }
                        }

                        // Cluster labels
                        ForEach(clusterCenters, id: \.clusterID) { center in
                            Text(layout.clusterNames[center.clusterID] ?? "Cluster \(center.clusterID)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(colorForCluster(center.clusterID).opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .position(center.position)
                                .offset(y: -45)
                        }
                    }
                    .scaleEffect(scale)
                    .offset(x: offset.width + dragOffset.width,
                            y: offset.height + dragOffset.height)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                            dragOffset = .zero
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(0.3, min(3.0, value))
                        }
                )
                .onAppear {
                    layout.buildGraph(from: repository.bits, in: geometry.size)
                }
            } // Close GeometryReader
            .opacity(isLoading ? 0 : 1)

            // Header overlay
                VStack {
                    headerView

                    Spacer()

                    // Selected node detail
                    if let node = selectedNode {
                        nodeDetailCard(node)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Legend
                    legendView
                }
                .opacity(isLoading ? 0 : 1)
                
                // Loading Screen overlay
                if isLoading {
                    VStack(spacing: 24) {
                        // Custom animated loading indicator
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                                .frame(width: 60, height: 60)
                            
                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(
                                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .frame(width: 60, height: 60)
                                .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                                .onAppear {
                                    isSpinning = true
                                }
                        }
                        
                        VStack(spacing: 8) {
                            Text("Analyzing Patterns")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Connecting your thoughts and memories...")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $bitToEdit) { bit in
                let clusterName = bit.clusterID.flatMap { layout.clusterNames[$0] }
                BitDetailView(bit: bit, clusterName: clusterName)
            }
        .onAppear {
            // Build the graph instantly from current DB state
            if let size = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.bounds.size {
                layout.buildGraph(from: repository.bits, in: size)
                
                // Hide loading overlay as soon as graph is initially ready
                withAnimation(.easeOut(duration: 0.6)) {
                    isLoading = false
                }
            }

            // Trigger background clustering (fire and forget)
            let aiManager = (repository as? LocalJournalRepository)?.aiProcessingManager
            Task.detached(priority: .background) {
                if let aiManager = aiManager {
                    print("[ClusterGraphView] Updating clusters in background...")
                    try? await aiManager.runClustering()
                }
            }
        }
        .onChange(of: repository.bits) {
            // Rebuild graph automatically if background clustering updates the DB
            if let size = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.bounds.size {
                layout.buildGraph(from: repository.bits, in: size)
            }
        }
        }

    // MARK: - Node View

    @ViewBuilder
    private func nodeView(_ node: GraphNode) -> some View {
        let isSelected = selectedNode?.id == node.id
        let isNoise = node.clusterID == nil || node.clusterID == -1
        let baseColor = isNoise ? Color.gray.opacity(0.4) : colorForCluster(node.clusterID)

        HStack(spacing: 6) {
            Text(node.emotion.emoji)
                .font(.caption)
            Text(node.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.white : baseColor.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: baseColor.opacity(isSelected ? 0.5 : 0.2), radius: isSelected ? 8 : 4, y: 2)
        )
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Knowledge Graph")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("\(layout.nodes.count) entries • \(clusterCount) clusters")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Refresh button
            Button {
                withAnimation {
                    if let size = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first?.windows.first?.bounds.size {
                        layout.buildGraph(from: repository.bits, in: size)
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Node Detail Card

    @ViewBuilder
    private func nodeDetailCard(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(node.emotion.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(node.emotion.rawValue)
                            .font(.caption)
                            .foregroundColor(node.emotion.color)

                        Text("•")
                            .foregroundColor(.gray)

                        Text(formatDate(node.createdAt))
                            .font(.caption)
                            .foregroundColor(.gray)

                        if let clusterID = node.clusterID, clusterID >= 0 {
                            Text("•")
                                .foregroundColor(.gray)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForCluster(clusterID))
                                    .frame(width: 8, height: 8)
                                Text("Cluster \(clusterID)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }

                Spacer()

                // Intensity indicator
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
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(.pink)
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
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Legend

    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(uniqueClusterIDs), id: \.self) { clusterID in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForCluster(clusterID))
                            .frame(width: 8, height: 8)
                        Text(clusterID == -1 ? "Unclustered" : (layout.clusterNames[clusterID] ?? "Cluster \(clusterID)"))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .onTapGesture {
                        if let center = clusterCenters.first(where: { $0.clusterID == clusterID }) {
                            // Find the screen center
                            if let window = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first {
                                let screenCenter = CGPoint(x: window.bounds.width / 2, y: window.bounds.height / 2)
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    offset = CGSize(
                                        width: (screenCenter.x - center.position.x) * scale,
                                        height: (screenCenter.y - center.position.y) * scale
                                    )
                                }
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
        let ids = Set(layout.nodes.map { $0.clusterID ?? -1 })
        return ids.sorted()
    }

    private var clusterCenters: [(clusterID: Int, position: CGPoint)] {
        let groups = Dictionary(grouping: layout.nodes.filter { $0.clusterID != nil && $0.clusterID! >= 0 }) { $0.clusterID! }
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
