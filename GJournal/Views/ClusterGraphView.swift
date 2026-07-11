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

    // Blur and transition state
    @State private var isAnimatingScale = false

    // MARK: - Computed Camera

    private var shouldApplyBlur: Bool {
        isPinching || gesturePanOffset != .zero || draggedNodeID != nil || isAnimatingScale
    }

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

    // MARK: - Coordinate Mapping (2D Viewport Sliding Window)

    private func screenPosition(for graphPosition: CGPoint, in viewportSize: CGSize) -> CGPoint {
        guard !viewportSize.width.isZero else { return graphPosition }
        let cx = viewportSize.width / 2
        let cy = viewportSize.height / 2
        
        // Zoom centered around the screen center, shifted by offset
        return CGPoint(
            x: cx + (graphPosition.x - cx) * effectiveScale + effectiveOffset.width,
            y: cy + (graphPosition.y - cy) * effectiveScale + effectiveOffset.height
        )
    }

    private func isNodeVisible(_ node: GraphNode, in viewportSize: CGSize) -> Bool {
        guard !viewportSize.width.isZero else { return true }
        let pos = screenPosition(for: node.position, in: viewportSize)
        let margin: CGFloat = 120.0 // Account for node view width (140/180)
        return pos.x >= -margin && pos.x <= viewportSize.width + margin &&
               pos.y >= -margin && pos.y <= viewportSize.height + margin
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()

            GeometryReader { geometry in
                let activeFocus = !layout.focusedNeighborIDs.isEmpty
                let viewportSize = geometry.size
                
                ZStack {
                    // 1. Edges Canvas (draws lines only)
                    Canvas { context, size in
                        let cx = size.width / 2
                        let cy = size.height / 2
                        
                        // Center-based scale and offset transform for drawing context
                        let tx = cx * (1 - effectiveScale) + effectiveOffset.width
                        let ty = cy * (1 - effectiveScale) + effectiveOffset.height
                        
                        context.translateBy(x: tx, y: ty)
                        context.scaleBy(x: effectiveScale, y: effectiveScale)
                        
                        let nodesByID = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0) })
                        
                        for edge in layout.edges {
                            guard let src = nodesByID[edge.sourceID],
                                  let dst = nodesByID[edge.targetID] else { continue }
                            
                            // 2D Sliding Window Culling: Skip edges entirely off-screen
                            guard isNodeVisible(src, in: size) || isNodeVisible(dst, in: size) else { continue }
                            
                            let isFocused = activeFocus && layout.focusedEdgeIDs.contains(edge.id)
                            let color = colorForCluster(edge.clusterID)
                            
                            let opacity: Double
                            if activeFocus {
                                opacity = isFocused ? 0.85 : 0.04
                            } else {
                                opacity = Double(max(0.2, min(0.9, edge.similarity))) * 0.45
                            }
                            
                            // Scale down line width relative to zoom so lines remain crisp and uniform
                            let lineWidth: CGFloat = (isFocused ? 2.5 : 1.0) / effectiveScale
                            
                            var path = Path()
                            path.move(to: src.position)
                            path.addLine(to: dst.position)
                            
                            context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: lineWidth)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true) // edges aren't VoiceOver-traversable
                    .blur(radius: shouldApplyBlur ? 2.0 : 0)
                    .opacity(shouldApplyBlur ? 0.55 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: shouldApplyBlur)

                    // 2. Nodes Layer
                    ForEach(layout.nodes) { node in
                        // Only render if within the active visible viewport (culls off-screen views)
                        if isNodeVisible(node, in: viewportSize) {
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
                            .scaleEffect(effectiveScale)
                            .position(screenPosition(for: node.position, in: viewportSize))
                            .blur(radius: shouldApplyBlur ? 0.7 : 0)
                            .animation(.easeInOut(duration: 0.15), value: shouldApplyBlur)
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
                            .accessibilityElement()
                            .accessibilityLabel(Text(nodeAccessibilityLabel(node)))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .onAppear {
                    graphSize = geometry.size
                    let bits = filterClusterID.map { id in repository.bits.filter { $0.clusterID == id } } ?? repository.bits
                    layout.buildGraph(from: bits, in: geometry.size, similarityEdges: filterClusterID != nil)
                    withAnimation(.easeOut(duration: 0.6)) { isLoading = false }
                }
            }
            .opacity(isLoading ? 0 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPinching else { return }
                        gesturePanOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isPinching else {
                            gesturePanOffset = .zero
                            return
                        }
                        let t = value.translation
                        if hypot(t.width, t.height) < 8 {
                            // Tap on empty space — clear selection
                            withAnimation(.spring(response: 0.3)) {
                                selectedNodeID = nil
                            }
                            layout.updateFocus(to: nil)
                        } else {
                            // Panning gesture — commit translate with a smooth spring release animation
                            isAnimatingScale = true
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                offset.width += t.width
                                offset.height += t.height
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isAnimatingScale = false
                            }
                        }
                        gesturePanOffset = .zero
                    }
            )
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
                        isAnimatingScale = true
                        // Smoothly animate the zoom release
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scale = max(0.3, min(3.0, scale * value))
                        }
                        gestureScale = 1.0
                        isPinching = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            isAnimatingScale = false
                        }
                    }
            )

            // Overlays (Header, Cards, Legend)
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
            
            // Zoom + / - Buttons Overlay
            if !isLoading {
                VStack(spacing: 12) {
                    Button {
                        isAnimatingScale = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scale = min(3.0, scale + 0.25)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            isAnimatingScale = false
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3).fontWeight(.bold).foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.85))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    
                    Button {
                        isAnimatingScale = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scale = max(0.3, scale - 0.25)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            isAnimatingScale = false
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.title3).fontWeight(.bold).foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.85))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, selectedNodeID != nil ? 110 : (filterClusterID == nil ? 90 : 30))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

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
        let cy = graphSize.height / 2
        let avgX = layout.nodes.reduce(0.0) { $0 + $1.position.x } / CGFloat(layout.nodes.count)
        let avgY = layout.nodes.reduce(0.0) { $0 + $1.position.y } / CGFloat(layout.nodes.count)
        withAnimation(.easeOut(duration: 0.45)) {
            offset = CGSize(width: effectiveScale * (cx - avgX), height: effectiveScale * (cy - avgY))
        }
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
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

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
                if node.isHub {
                    Image(systemName: "circle.grid.hex.fill")
                        .font(.title2)
                        .foregroundColor(colorForCluster(node.clusterID))
                } else {
                    Text(node.emotion.emoji).font(.title2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title).font(.headline).foregroundColor(.white).lineLimit(1)

                    HStack(spacing: 8) {
                        if node.isHub {
                            Text("Cluster Centroid Hub").font(.caption).foregroundColor(.gray)
                        } else {
                            Text(node.emotion.rawValue).font(.caption).foregroundColor(node.emotion.color)
                            Text("\u{2022}").foregroundColor(.gray)
                            Text(node.createdAt.dayMonth).font(.caption).foregroundColor(.gray)
                        }

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

                if !node.isHub {
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
                            isAnimatingScale = true
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                offset = CGSize(
                                    width: effectiveScale * (graphSize.width / 2 - center.position.x),
                                    height: effectiveScale * (graphSize.height / 2 - center.position.y)
                                )
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isAnimatingScale = false
                            }
                            if clusterID >= 0 {
                                let hubID = uuidForCluster(id: clusterID)
                                selectedNodeID = hubID
                                layout.updateFocus(to: hubID)
                            } else {
                                selectedNodeID = nil
                                layout.updateFocus(to: nil)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    // MARK: - VoiceOver

    /// Spoken description for a node in the knowledge graph. Canvas edges are hidden from
    /// VoiceOver, so each node carries its own cluster/emotion context.
    private func nodeAccessibilityLabel(_ node: GraphNode) -> String {
        let clusterName: String? = node.clusterID.flatMap { id in
            id >= 0 ? (layout.clusterNames[id] ?? String(localized: "Cluster \(id)")) : nil
        }
        if node.isHub {
            let name = clusterName ?? node.title
            return String(localized: "\(name) cluster hub")
        }
        var label = String(localized: "\(node.title). Emotion \(node.emotion.rawValue).")
        if let clusterName {
            label += " " + String(localized: "In \(clusterName).")
        } else {
            label += " " + String(localized: "Unclustered.")
        }
        return label
    }

    // MARK: - Helpers

    private func uuidForCluster(id: Int) -> UUID {
        let hex = String(format: "%012lx", id)
        return UUID(uuidString: "00000000-0000-0000-0000-\(hex)") ?? UUID()
    }

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
        let scale: CGFloat = isFocused ? 1.25 : (isDimmed ? 0.95 : (isSelected || isNeighbor ? 1.15 : 1.0))
        let opacity: Double = isDimmed ? 0.25 : 1.0
        
        if node.isHub {
            // Render Hub Node (Centroid)
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.hex.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                Text(node.title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(opacity))
            .padding(.horizontal, 12)
            .frame(width: 180, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [clusterColor.opacity(0.95), clusterColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(opacity)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color.white.opacity(opacity) : Color.white.opacity(0.25 * opacity),
                        lineWidth: isSelected ? 2.5 : 1.5
                    )
            )
            .shadow(
                color: clusterColor.opacity(isFocused ? 0.7 : (isDimmed ? 0.0 : 0.45)),
                radius: isFocused ? 12 : 6,
                x: 0,
                y: isFocused ? 6 : 3
            )
            .scaleEffect(scale)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: scale)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: opacity)
        } else {
            // Render Normal Node
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
}
