import Foundation
import SwiftData

// MARK: - Schema V1 (baseline)
//
// Wraps the current Bit and Cluster models as the baseline schema version.
// Future schema changes (e.g., adding BehavioralTag in Phase 2) arrive as new
// VersionedSchema enums with corresponding lightweight migration stages.
//
// Usage: GJournalApp.makeModelContainer() creates the container via
//        Schema(versionedSchema: SchemaV1.self) + GJournalMigrationPlan.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Bit.self, Cluster.self]
    }
}

// MARK: - Migration Plan

enum GJournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migration stages yet — SchemaV1 is the baseline.
        // When SchemaV2 is added (e.g., for BehavioralTag), add a stage here:
        //   .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        // For complex migrations, use .custom() with willMigrate/didMigrate closures.
        []
    }
}
