//
//  JournalRepositoryProtocol.swift
//  GJournal
//
//  Protocol defining the journal repository interface for dependency injection.
//

import Foundation
import SwiftData

/// Protocol defining all repository operations for journal entries (Bits).
/// Conforming types must be ObservableObject to support SwiftUI data binding.
protocol JournalRepositoryProtocol: ObservableObject {
    /// All loaded bits, sorted by last modified descending
    var bits: [Bit] { get }

    /// All soft-deleted bits, sorted by deletion date descending
    var deletedBits: [Bit] { get }

    /// Current error message, if any
    var errorMessage: String? { get set }

    // MARK: - Configuration

    /// Configure the repository with a SwiftData ModelContext
    func configure(with modelContext: ModelContext)

    // MARK: - CRUD Operations

    func createBit(
        title: String?,
        feel: String,
        event: String,
        action: String,
        intensity: Int
    )

    func updateBit(
        id: UUID,
        title: String?,
        feel: String,
        event: String,
        action: String,
        intensity: Int
    )

    func deleteBit(id: UUID)
    func restoreBit(id: UUID)
    func permanentlyDeleteBit(id: UUID)
    func toggleHideBit(id: UUID)

    // MARK: - Query Operations

    func getBits(for date: Date) -> [Bit]
    func getDaysWithBits() -> Set<Date>
    func canEdit(bit: Bit) -> Bool
    func canCreate(for date: Date) -> Bool
    func getTopEmotionsLast30Days() -> [(emotion: Emotion, count: Int, dates: [Date])]

    // MARK: - Search & Filter

    func searchBits(
        query: String,
        emotions: [Emotion]?,
        dateRange: ClosedRange<Date>?,
        intensityRange: ClosedRange<Int>?,
        clusterIDs: [Int]?
    ) -> [Bit]
}
