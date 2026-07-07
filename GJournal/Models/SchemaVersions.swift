import Foundation
import SwiftData

// MARK: - Schema V1 (baseline)
//
// Wraps the original Bit and Cluster models as the baseline schema version.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Bit.self, Cluster.self]
    }
}

// MARK: - Schema V2 (behavioral tags)
//
// Additive change for Pillar A/§2.0: introduces the `BehavioralTag` registry model and the
// denormalized `Bit.tagLemmasData` optional attribute. Both are additive, so V1→V2 is a
// lightweight migration — existing journals are preserved untouched.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Bit.self, Cluster.self, BehavioralTag.self]
    }
}

// MARK: - Migration Plan

enum GJournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            // Additive only (new model + new optional attribute) → lightweight.
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }
}
