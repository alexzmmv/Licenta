import Foundation

struct ClusterAssignment {
    let bitID: UUID

    let clusterID: Int

    var isNoise: Bool {
        clusterID == -1
    }
}
