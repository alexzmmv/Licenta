import SwiftUI
import Combine

// MARK: - Graph Data Models

struct GraphNode: Identifiable, Equatable {
    let id: UUID
    let title: String
    let emotion: Emotion
    let clusterID: Int?
    let createdAt: Date
    let intensity: Int

    var position: CGPoint
    var velocity: CGPoint = .zero

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.emotion == rhs.emotion &&
        lhs.clusterID == rhs.clusterID &&
        lhs.createdAt == rhs.createdAt &&
        lhs.intensity == rhs.intensity &&
        lhs.position == rhs.position &&
        lhs.velocity == rhs.velocity
    }
}

struct GraphEdge: Identifiable {
    let id = UUID()
    let sourceID: UUID
    let targetID: UUID
    let clusterID: Int
    var similarity: Float = 1.0
}

// MARK: - Force-Directed Layout Engine

class ForceDirectedLayout: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var clusterNames: [Int: String] = [:]
    @Published var isSimulating = false
    
    @Published var focusedNeighborIDs: Set<UUID> = []
    @Published var focusedEdgeIDs: Set<UUID> = []
    
    func updateFocus(to nodeID: UUID?) {
        guard let focusID = nodeID else {
            focusedNeighborIDs.removeAll()
            focusedEdgeIDs.removeAll()
            return
        }
        
        var neighborIDs = Set<UUID>([focusID])
        var edgeIDs = Set<UUID>()
        
        for edge in edges {
            if edge.sourceID == focusID || edge.targetID == focusID {
                edgeIDs.insert(edge.id)
                neighborIDs.insert(edge.sourceID == focusID ? edge.targetID : edge.sourceID)
            }
        }
        
        focusedNeighborIDs = neighborIDs
        focusedEdgeIDs = edgeIDs
    }

    func buildGraph(from bits: [Bit], in size: CGSize, similarityEdges: Bool = false) {
        guard !bits.isEmpty else {
            nodes = []; edges = []; clusterNames = [:]
            return
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let bitsByCluster = Dictionary(grouping: bits) { $0.clusterID ?? -1 }
        let bitsDict = Dictionary(uniqueKeysWithValues: bits.map { ($0.id, $0) })
        
        // Sort clusters by node count descending (largest clusters first)
        let sortedClusters = bitsByCluster.keys.sorted { id1, id2 in
            let count1 = bitsByCluster[id1]?.count ?? 0
            let count2 = bitsByCluster[id2]?.count ?? 0
            return count1 > count2
        }

        var initialNodes: [GraphNode] = []
        var currentSpiralRadius: CGFloat = 0
        let goldenAngle: CGFloat = 137.5 * .pi / 180.0 // ~2.39996 radians

        for (clusterIndex, clusterID) in sortedClusters.enumerated() {
            let clusterBits = bitsByCluster[clusterID] ?? []
            let nodeCount = clusterBits.count
            
            // Calculate a radius representing the area needed by this cluster
            let clusterRadius = 30.0 + 10.0 * sqrt(CGFloat(nodeCount))
            
            if clusterIndex > 0 {
                // Grow the spiral radius based on cluster size to avoid overlaps
                currentSpiralRadius += clusterRadius * 0.5 + 20.0
            } else {
                currentSpiralRadius = 0 // Largest cluster at the center
            }

            let angle = CGFloat(clusterIndex) * goldenAngle
            let clusterCenter = CGPoint(
                x: center.x + cos(angle) * currentSpiralRadius,
                y: center.y + sin(angle) * currentSpiralRadius
            )

            // Local node spread within the cluster
            let localRadius = 15.0 + 8.0 * sqrt(CGFloat(nodeCount))

            for (bitIndex, bit) in clusterBits.enumerated() {
                let position: CGPoint
                if let gx = bit.graphX, let gy = bit.graphY, !similarityEdges {
                    position = CGPoint(x: CGFloat(gx), y: CGFloat(gy))
                } else {
                    let bitAngle = (CGFloat(bitIndex) / CGFloat(max(1, nodeCount))) * 2 * .pi
                    let jitter = CGFloat.random(in: -10...10)
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

        var newEdges: [GraphEdge] = []
        var newClusterNames: [Int: String] = [:]
        let clusterGroups = Dictionary(
            grouping: initialNodes.filter { $0.clusterID != nil && $0.clusterID! >= 0 }
        ) { $0.clusterID! }

        for (clusterID, clusterNodes) in clusterGroups {
            let clusterBits = bitsByCluster[clusterID] ?? []
            if let persistedName = clusterBits.compactMap({ $0.cluster?.name }).first {
                newClusterNames[clusterID] = persistedName
            } else {
                newClusterNames[clusterID] = ClusterNamer.generateName(for: clusterBits, fallbackID: clusterID)
            }

            if similarityEdges {
                let threshold: Float = 0.65
                for i in 0..<clusterNodes.count {
                    for j in (i + 1)..<clusterNodes.count {
                        let bitA = bitsDict[clusterNodes[i].id]
                        let bitB = bitsDict[clusterNodes[j].id]
                        if let nA = SemanticUtils.normalised(bitA?.embedding),
                           let nB = SemanticUtils.normalised(bitB?.embedding) {
                            let sim = SemanticUtils.cosineSimilarity(nA, nB)
                            if sim >= threshold {
                                newEdges.append(GraphEdge(
                                    sourceID: clusterNodes[i].id,
                                    targetID: clusterNodes[j].id,
                                    clusterID: clusterID,
                                    similarity: sim
                                ))
                            }
                        }
                    }
                }
            } else {
                if clusterNodes.count > 1 {
                    let hub = clusterNodes[0]
                    for i in 1..<clusterNodes.count {
                        newEdges.append(GraphEdge(sourceID: hub.id, targetID: clusterNodes[i].id, clusterID: clusterID))
                    }
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
            
            let nodeIndexDict = Dictionary(uniqueKeysWithValues: initialNodes.enumerated().map { ($0.element.id, $0.offset) })
            let edgeIndices: [(Int, Int)] = newEdges.compactMap { edge in
                guard let si = nodeIndexDict[edge.sourceID], let ti = nodeIndexDict[edge.targetID] else { return nil }
                return (si, ti)
            }
            
            let clusterGroupsIndices: [[Int]] = {
                let grouped = Dictionary(
                    grouping: initialNodes.enumerated().filter { $0.element.clusterID != nil && $0.element.clusterID! >= 0 }
                ) { $0.element.clusterID! }
                return Array(grouped.values.map { $0.map { $0.offset } })
            }()

            for _ in 0..<maxIters {
                let prevPositions = simulationNodes.map { $0.position }
                simulationNodes = self.computeStep(
                    nodes: simulationNodes,
                    edgeIndices: edgeIndices,
                    clusterIndices: clusterGroupsIndices,
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
        edgeIndices: [(Int, Int)],
        clusterIndices: [[Int]],
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

        for (si, ti) in edgeIndices {
            let dx = nodes[ti].position.x - nodes[si].position.x
            let dy = nodes[ti].position.y - nodes[si].position.y
            forces[si].x += dx * attraction; forces[si].y += dy * attraction
            forces[ti].x -= dx * attraction; forces[ti].y -= dy * attraction
        }

        // 1. Compute cluster centroids and radii
        var centroids = Array(repeating: CGPoint.zero, count: clusterIndices.count)
        var clusterRadii = Array(repeating: CGFloat(0), count: clusterIndices.count)
        
        for (cIdx, indices) in clusterIndices.enumerated() {
            guard !indices.isEmpty else { continue }
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            for idx in indices {
                sumX += nodes[idx].position.x
                sumY += nodes[idx].position.y
            }
            let count = CGFloat(indices.count)
            centroids[cIdx] = CGPoint(x: sumX / count, y: sumY / count)
            // Area-based radius: base radius + factor * sqrt(count)
            clusterRadii[cIdx] = 30.0 + 10.0 * sqrt(count)
        }
        
        // 2. Intra-cluster attraction (pull nodes to their centroid)
        for (cIdx, indices) in clusterIndices.enumerated() {
            let clusterCenter = centroids[cIdx]
            for idx in indices {
                forces[idx].x += (clusterCenter.x - nodes[idx].position.x) * 0.1
                forces[idx].y += (clusterCenter.y - nodes[idx].position.y) * 0.1
            }
        }
        
        // 3. Inter-cluster centroid repulsion (push cluster centroids away from each other)
        var clusterForces = Array(repeating: CGPoint.zero, count: clusterIndices.count)
        for i in 0..<clusterIndices.count {
            for j in (i + 1)..<clusterIndices.count {
                let dx = centroids[i].x - centroids[j].x
                let dy = centroids[i].y - centroids[j].y
                let dist = sqrt(dx * dx + dy * dy)
                let actualDist = max(dist, 1.0)
                
                // Desired minimum distance between cluster boundaries
                let minDistBetween = clusterRadii[i] + clusterRadii[j] + 60.0 // 60pt safety margin
                if dist < minDistBetween {
                    let overlap = minDistBetween - dist
                    // Apply a push force proportional to the overlap
                    let forceMag = overlap * 0.15
                    let fx = (dx / actualDist) * forceMag
                    let fy = (dy / actualDist) * forceMag
                    
                    clusterForces[i].x += fx
                    clusterForces[i].y += fy
                    clusterForces[j].x -= fx
                    clusterForces[j].y -= fy
                }
            }
        }
        
        // 4. Apply cluster centroid repulsion forces to all nodes in each cluster
        for (cIdx, indices) in clusterIndices.enumerated() {
            let cf = clusterForces[cIdx]
            for idx in indices {
                forces[idx].x += cf.x
                forces[idx].y += cf.y
            }
        }

        for i in 0..<nodes.count {
            forces[i].x += (center.x - nodes[i].position.x) * gravity
            forces[i].y += (center.y - nodes[i].position.y) * gravity
        }

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
