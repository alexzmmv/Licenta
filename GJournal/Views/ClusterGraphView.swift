import SwiftUI
import SwiftData

// MARK: - Cluster Graph View

struct ClusterGraphView: View {
    @ObservedObject var repository: BaseJournalRepository
    var filterClusterID: Int? = nil
    @StateObject private var layout = ForceDirectedLayout()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    // MARK: - Interaction State

    @State private var selectedNodeID: UUID?
    @State private var draggedNodeID: UUID?

    // Camera state (committed values)
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    // In-progress gesture deltas
    @State private var gestureScale: CGFloat = 1.0
    @State private var gesturePanOffset: CGSize = .zero

    // Multi-touch detection
    @State private var isPinching = false

    // View state
    @State private var isLoading = true
    @State private var isSpinning = false
    @State private var bitToEdit: Bit?
    @State private var graphSize: CGSize = .zero

    // MARK: - Computed Camera

    private var effectiveScale: CGFloat {
        max(0.3, min(3.0, scale * gestureScale))
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: offset.width + gesturePanOffset.width,
            height: offset.height + gesturePanOffset.height
        )
    }

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

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()

            GeometryReader { geometry in
                let activeFocus = !layout.focusedNeighborIDs.isEmpty
                
                // Full-screen background area for panning and selection clearing
                // This sits outside the transformed ZStack so it covers the 100% full screen area at all times,
                // allowing panning indefinitely even when the graph is zoomed out or panned away.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedNodeID = nil
                        }
                        layout.updateFocus(to: nil)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                guard !isPinching else { return }
                                gesturePanOffset = value.translation
                            }
                            .onEnded { value in
                                guard !isPinching else {
                                    gesturePanOffset = .zero
                                    return
                                }
                                offset.width += value.translation.width
                                offset.height += value.translation.height
                                gesturePanOffset = .zero
                            }
                    )

                ZStack {
                    // 1. Edges Canvas (draws lines only)
                    Canvas { context, size in
                        let nodesByID = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0) })
                        
                        // Pass 1: Background dimmed edges
                        var bgPath = Path()
                        for edge in layout.edges {
                            if activeFocus && layout.focusedEdgeIDs.contains(edge.id) { continue }
                            guard let src = nodesByID[edge.sourceID],
                                  let dst = nodesByID[edge.targetID] else { continue }
                            bgPath.move(to: src.position)
                            bgPath.addLine(to: dst.position)
                        }
                        context.stroke(bgPath, with: .color(Color.gray.opacity(activeFocus ? 0.03 : 0.25)), lineWidth: 1)

                        // Pass 2: Foreground highlighted edges
                        if activeFocus {
                            var fgPath = Path()
                            for edge in layout.edges {
                                if !layout.focusedEdgeIDs.contains(edge.id) { continue }
                                guard let src = nodesByID[edge.sourceID],
                                      let dst = nodesByID[edge.targetID] else { continue }
                                fgPath.move(to: src.position)
                                fgPath.addLine(to: dst.position)
                            }
                            context.stroke(fgPath, with: .color(Color.white.opacity(0.85)), lineWidth: 2)
                        }
                    }
                    .allowsHitTesting(false)

                    // 2. Nodes Layer
                    ForEach(layout.nodes) { node in
                        let isSelected = node.id == selectedNodeID
                        let isDimmed = activeFocus && !layout.focusedNeighborIDs.contains(node.id)
                        let isNeighbor = activeFocus && layout.focusedNeighborIDs.contains(node.id) && node.id != selectedNodeID
                        let isFocused = node.id == (draggedNodeID ?? selectedNodeID)
                        
                        NodeView(
                            node: node,
                            isSelected: isSelected,
                            isDimmed: isDimmed,
                            isFocused: isFocused,
                            isNeighbor: isNeighbor,
                            clusterColor: colorForCluster(node.clusterID)
                        )
                        .position(node.position)
                        .onTapGesture {
                            let newSelection = (selectedNodeID == node.id) ? nil : node.id
                            withAnimation(.spring(response: 0.3)) {
                                selectedNodeID = newSelection
                            }
                            layout.updateFocus(to: newSelection)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    guard !isPinching else { return }
                                    if draggedNodeID == nil {
                                        draggedNodeID = node.id
                                        layout.updateFocus(to: node.id)
                                    }
                                }
                                .onEnded { _ in
                                    if draggedNodeID != nil {
                                        draggedNodeID = nil
                                        layout.updateFocus(to: selectedNodeID)
                                    }
                                }
                        )
                    }

                    // 3. Cluster centers / titles
                    ForEach(clusterCenters, id: \.clusterID) { center in
                        let name = layout.clusterNames[center.clusterID] ?? "Cluster \(center.clusterID)"
                        Text(name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(colorForCluster(center.clusterID).opacity(0.85))
                            .position(x: center.position.x, y: center.position.y - 32)
                            .allowsHitTesting(false)
                    }
                }
                .offset(effectiveOffset)
                .scaleEffect(effectiveScale)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            isPinching = true
                            if draggedNodeID != nil {
                                draggedNodeID = nil
                                layout.updateFocus(to: selectedNodeID)
                            }
                            gestureScale = value
                        }
                        .onEnded { value in
                            scale = max(0.3, min(3.0, scale * value))
                            gestureScale = 1.0
                            isPinching = false
                        }
                )
                .onAppear {
                    graphSize = geometry.size
                    let bits = filterClusterID.map { id in repository.bits.filter { $0.clusterID == id } } ?? repository.bits
                    layout.buildGraph(from: bits, in: geometry.size, similarityEdges: filterClusterID != nil)
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
                if filterClusterID == nil { legendView }
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
            BitDetailView(
                bit: bit,
                clusterName: bit.clusterID.flatMap { layout.clusterNames[$0] },
                allBits: repository.bits
            )
        }
        .onChange(of: repository.bits) {
            guard !graphSize.width.isZero else { return }
            let bits = filterClusterID.map { id in repository.bits.filter { $0.clusterID == id } } ?? repository.bits
            layout.buildGraph(from: bits, in: graphSize, similarityEdges: filterClusterID != nil)
        }
        .onChange(of: layout.isSimulating) { _, isNowSimulating in
            guard !isNowSimulating else { return }
            if filterClusterID == nil {
                for node in layout.nodes {
                    if let bit = repository.bits.first(where: { $0.id == node.id }) {
                        bit.graphX = Double(node.position.x)
                        bit.graphY = Double(node.position.y)
                    }
                }
                try? modelContext.save()
            } else {
                centerOnNodes()
            }
        }
    }

    // MARK: - Camera

    private func centerOnNodes() {
        guard !layout.nodes.isEmpty, !graphSize.width.isZero else { return }
        let cx = graphSize.width / 2
        let cy = geometryReaderWorkaroundCenter().y // fallback helper
        let avgX = layout.nodes.reduce(0.0) { $0 + $1.position.x } / CGFloat(layout.nodes.count)
        let avgY = layout.nodes.reduce(0.0) { $0 + $1.position.y } / CGFloat(layout.nodes.count)
        withAnimation(.easeOut(duration: 0.45)) {
            offset = CGSize(width: effectiveScale * (cx - avgX), height: effectiveScale * (graphSize.height / 2 - avgY))
        }
    }
    
    private func geometryReaderWorkaroundCenter() -> CGPoint {
        CGPoint(x: graphSize.width / 2, y: graphSize.height / 2)
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
                Text(filterClusterID.flatMap { layout.clusterNames[$0] } ?? "Knowledge Graph")
                    .font(.title3).fontWeight(.bold).foregroundColor(.white)
                Text(filterClusterID != nil
                     ? "\(layout.nodes.count) entries"
                     : "\(layout.nodes.count) entries \u{2022} \(clusterCount) clusters")
                    .font(.caption).foregroundColor(.gray)
            }

            Spacer()

            Button {
                let bits = filterClusterID.map { id in repository.bits.filter { $0.clusterID == id } } ?? repository.bits
                withAnimation { layout.buildGraph(from: bits, in: graphSize, similarityEdges: filterClusterID != nil) }
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
                        Text("\u{2022}").foregroundColor(.gray)
                        Text(node.createdAt.dayMonth).font(.caption).foregroundColor(.gray)

                        if let clusterID = node.clusterID, clusterID >= 0 {
                            Text("\u{2022}").foregroundColor(.gray)
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
                                    width: effectiveScale * (graphSize.width / 2 - center.position.x),
                                    height: effectiveScale * (graphSize.height / 2 - center.position.y)
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
}

// MARK: - Node View

struct NodeView: View {
    let node: GraphNode
    let isSelected: Bool
    let isDimmed: Bool
    let isFocused: Bool
    let isNeighbor: Bool
    let clusterColor: Color
    
    var body: some View {
        let isNoise = node.clusterID == nil || node.clusterID == -1
        let scale: CGFloat = isFocused ? 1.2 : (isDimmed ? 0.9 : (isSelected || isNeighbor ? 1.1 : 1.0))
        let opacity: Double = isDimmed ? 0.2 : 1.0
        
        HStack(spacing: 6) {
            Text(node.emotion.emoji)
                .font(.caption)
            Text(node.title)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundColor(Color.white.opacity(opacity))
        .padding(.horizontal, 8)
        .frame(width: 140, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? clusterColor.opacity(0.3 * opacity) : Color(red: 0.1, green: 0.1, blue: 0.12).opacity(opacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.white.opacity(opacity) : clusterColor.opacity(isNoise ? (0.4 * opacity) : (0.8 * opacity)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: .black.opacity(isFocused ? 0.8 : (isNeighbor ? 0.45 : 0.0)),
            radius: isFocused ? 8 : (isNeighbor ? 4 : 0),
            x: 0,
            y: isFocused ? 4 : (isNeighbor ? 2 : 0)
        )
        .scaleEffect(scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: opacity)
    }
}
