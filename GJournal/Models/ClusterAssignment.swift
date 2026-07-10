import Foundation

struct ClusterAssignment: Sendable {
    let bitID: UUID

    let clusterID: Int

    nonisolated var isNoise: Bool {
        clusterID == -1
    }
}
