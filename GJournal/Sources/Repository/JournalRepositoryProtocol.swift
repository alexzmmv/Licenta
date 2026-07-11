import Foundation
import SwiftData

protocol JournalRepositoryProtocol: ObservableObject {
    var bits: [Bit] { get }

    var deletedBits: [Bit] { get }

    var errorMessage: String? { get set }

    // MARK: - Configuration

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
