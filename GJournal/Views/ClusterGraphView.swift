import SwiftUI
import SwiftData

// MARK: - Cluster Graph View

struct ClusterGraphView: View {
    @ObservedObject var repository: BaseJournalRepository
    var filterClusterID: Int? = nil
    @StateObject private var layout = ForceDirectedLayout()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var selectedNodeID: UUID?
    @State private var draggedNodeID: UUID?
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
                Canvas { context, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let tx = offset.width + dragOffset.width
                    let ty = offset.height + dragOffset.height
                    context.transform = CGAffineTransform(
                        a: scale, b: 0, c: 0, d: scale,
                        tx: cx * (1 - scale) + tx,
                        ty: cy * (1 - scale) + ty
                    )

                    let activeFocus = layout.focusedNeighborIDs.isEmpty ? false : true

                    // PASS 1: BACKGROUND (Dimmed)
                    for edge in layout.edges {
                        if activeFocus && layout.focusedEdgeIDs.contains(edge.id) { continue }
                        guard let src = layout.nodes.first(where: { $0.id == edge.sourceID }),
                              let dst = layout.nodes.first(where: { $0.id == edge.targetID }) else { continue }
                        var path = Path()
                        path.move(to: src.position)
                        path.addLine(to: dst.position)
                        let opacity = activeFocus ? 0.05 : Double(max(0.2, min(0.9, edge.similarity))) * 0.6
                        context.stroke(path, with: .color(colorForCluster(edge.clusterID).opacity(opacity)), lineWidth: 1)
                    }

                    for node in layout.nodes {
                        if activeFocus && layout.focusedNeighborIDs.contains(node.id) { continue }
                        drawNode(node, context: &context, isSelected: false, isDimmed: activeFocus, isFocused: false)
                    }

                    // PASS 2: FOREGROUND (Focused)
                    if activeFocus {
                        for edge in layout.edges {
                            if !layout.focusedEdgeIDs.contains(edge.id) { continue }
                            guard let src = layout.nodes.first(where: { $0.id == edge.sourceID }),
                                  let dst = layout.nodes.first(where: { $0.id == edge.targetID }) else { continue }
                            var path = Path()
                            path.move(to: src.position)
                            path.addLine(to: dst.position)
                            context.stroke(path, with: .color(colorForCluster(edge.clusterID).opacity(1.0)), lineWidth: 2)
                        }

                        for node in layout.nodes {
                            if !layout.focusedNeighborIDs.contains(node.id) { continue }
                            let isTarget = node.id == (draggedNodeID ?? selectedNodeID)
                            drawNode(node, context: &context, isSelected: node.id == selectedNodeID, isDimmed: false, isFocused: isTarget)
                        }
                    }

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
                            
                            // Temporary focus on drag
                            let graphPoint = adjustPoint(value.location)
                            if let hitID = hitTest(at: graphPoint) {
                                if draggedNodeID != hitID {
                                    draggedNodeID = hitID
                                    layout.updateFocus(to: hitID)
                                }
                            }
                        }
                        .onEnded { value in
                            let t = value.translation
                            dragOffset = .zero
                            let graphPoint = adjustPoint(value.startLocation)
                            let hitID = hitTest(at: graphPoint)
                            
                            if hypot(t.width, t.height) < 8 {
                                withAnimation(.spring(response: 0.3)) {
                                    if let id = hitID {
                                        selectedNodeID = (selectedNodeID == id) ? nil : id
                                    } else {
                                        selectedNodeID = nil
                                    }
                                }
                            } else {
                                offset.width += t.width
                                offset.height += t.height
                            }
                            
                            // Clear drag focus and update layout to current selection
                            draggedNodeID = nil
                            layout.updateFocus(to: selectedNodeID)
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture().onChanged { value in
                        scale = max(0.3, min(3.0, value))
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

    // MARK: - Node Rendering

    private func drawNode(_ node: GraphNode, context: inout GraphicsContext, isSelected: Bool, isDimmed: Bool, isFocused: Bool) {
        let isNoise = node.clusterID == nil || node.clusterID == -1
        let clusterColor = colorForCluster(node.clusterID)
        
        let scale: CGFloat = isFocused ? 1.2 : (isDimmed ? 0.9 : (isSelected || !isDimmed && layout.focusedNeighborIDs.contains(node.id) ? 1.1 : 1.0))
        let opacity: Double = isDimmed ? 0.2 : 1.0
        
        let rect = CGRect(x: node.position.x - (70 * scale), y: node.position.y - (18 * scale), width: 140 * scale, height: 36 * scale)
        let nodePath = Path(roundedRect: rect, cornerRadius: 12 * scale)
        
        var shadowContext = context
        if !isDimmed && layout.focusedNeighborIDs.contains(node.id) {
            shadowContext.addFilter(.shadow(color: .black.opacity(isFocused ? 0.8 : 0.4), radius: isFocused ? 8 : 4, x: 0, y: isFocused ? 4 : 2))
        }

        shadowContext.fill(nodePath, with: .color(
            isSelected ? clusterColor.opacity(0.3 * opacity) : Color(red: 0.1, green: 0.1, blue: 0.12).opacity(opacity)
        ))
        shadowContext.stroke(nodePath, with: .color(
            isSelected ? Color.white.opacity(opacity) : clusterColor.opacity(isNoise ? (0.4 * opacity) : (0.8 * opacity))
        ), lineWidth: isSelected ? 2 : 1)

        shadowContext.draw(
            Text("\(node.emotion.emoji) \(node.title)").font(.caption2).foregroundColor(Color.white.opacity(opacity)),
            in: CGRect(x: rect.minX + 6, y: rect.minY, width: rect.width - 12, height: rect.height)
        )
    }

    // MARK: - Camera

    private func centerOnNodes() {
        guard !layout.nodes.isEmpty, !graphSize.width.isZero else { return }
        let cx = graphSize.width / 2
        let cy = graphSize.height / 2
        let avgX = layout.nodes.reduce(0.0) { $0 + $1.position.x } / CGFloat(layout.nodes.count)
        let avgY = layout.nodes.reduce(0.0) { $0 + $1.position.y } / CGFloat(layout.nodes.count)
        withAnimation(.easeOut(duration: 0.45)) {
            offset = CGSize(width: scale * (cx - avgX), height: scale * (cy - avgY))
        }
    }

    // MARK: - Manual Hit-Testing

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
}
