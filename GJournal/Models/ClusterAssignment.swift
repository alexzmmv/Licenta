//
//  ClusterAssignment.swift
//  GJournal
//
//  Model for DBSCAN cluster assignment results.
//

import Foundation

/// Represents the cluster assignment for a single journal entry.
struct ClusterAssignment {
    /// The Bit's UUID
    let bitID: UUID

    /// The assigned cluster ID. -1 indicates noise (no cluster).
    let clusterID: Int

    /// Whether this entry is considered noise by DBSCAN
    var isNoise: Bool {
        clusterID == -1
    }
}
