import Foundation
import Combine
import SwiftData

open class BaseJournalRepository: ObservableObject {
    @Published var bits: [Bit] = []
    @Published var deletedBits: [Bit] = []
    @Published var errorMessage: String? = nil

    let hybridSearch = HybridSearchService()
    var modelContext: ModelContext?

    init(bool loadSampleDataInit: Bool = false) {
        // Override in subclass
    }
    
    open func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadBitsFromContext()
    }
    
    open func loadBitsFromContext() {
        guard let modelContext = modelContext else { return }
        
        let activePredicate = #Predicate<Bit> { bit in
            bit.deletedAt == nil
        }
        let activeDescriptor = FetchDescriptor<Bit>(
            predicate: activePredicate,
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        
        let deletedPredicate = #Predicate<Bit> { bit in
            bit.deletedAt != nil
        }
        let deletedDescriptor = FetchDescriptor<Bit>(
            predicate: deletedPredicate,
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        
        do {
            bits = try modelContext.fetch(activeDescriptor)
            deletedBits = try modelContext.fetch(deletedDescriptor)
            hybridSearch.rebuild(from: bits)
            AppLogger.log("[Repository] Loaded \(bits.count) active, \(deletedBits.count) deleted bits")
        } catch {
            AppLogger.error("[Repository] Failed to load bits: \(error)")
            bits = []
            deletedBits = []
        }
    }

    // MARK: - CRUD operations (override in subclasses)

    func createBit(title: String?, feel: String, event: String, action: String, intensity: Int) {
        // Override in subclass
    }

    func updateBit(id: UUID, title: String?, feel: String, event: String, action: String, intensity: Int) {
        // Override in subclass
    }

    func deleteBit(id: UUID) {
        // Override in subclass
    }

    func restoreBit(id: UUID) {
        // Override in subclass
    }

    func permanentlyDeleteBit(id: UUID) {
        // Override in subclass
    }

    func toggleHideBit(id: UUID) {
        // Override in subclass
    }

    // MARK: - Query Operations

    func getBits(for date: Date) -> [Bit] {
        return bits.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
            .sorted { first, second in
                if first.isHidden != second.isHidden {
                    return (first.isHidden ? 1 : 0) < (second.isHidden ? 1 : 0)
                }
                return first.lastModified > second.lastModified
            }
    }

    func getDaysWithBits() -> Set<Date> {
        let calendar = Calendar.current
        return Set(bits.map { calendar.startOfDay(for: $0.createdAt) })
    }

    func canEdit(bit: Bit) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? Date.distantPast
        let bitDay = calendar.startOfDay(for: bit.createdAt)

        return bitDay == today || bitDay == yesterday
    }

    func canCreate(for date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDateInToday(date)
    }

    func getTopEmotionsLast30Days() -> [(emotion: Emotion, count: Int, dates: [Date])] {
        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? Date.distantPast

        let recentBits = bits.filter { $0.createdAt >= thirtyDaysAgo && $0.createdAt <= now && !$0.isHidden }

        var emotionData: [Emotion: (dates: Set<Date>, totalIntensity: Int)] = [:]

        for bit in recentBits {
            let day = calendar.startOfDay(for: bit.createdAt)
            let emotion = bit.emotion
            if var data = emotionData[emotion] {
                data.dates.insert(day)
                data.totalIntensity += bit.intensity
                emotionData[emotion] = data
            } else {
                emotionData[emotion] = (dates: [day], totalIntensity: bit.intensity)
            }
        }

        return emotionData
            .map { (emotion: $0.key, count: $0.value.dates.count, dates: Array($0.value.dates).sorted(), totalIntensity: $0.value.totalIntensity) }
            .sorted { first, second in
                if first.count != second.count {
                    return first.count > second.count
                }
                return first.totalIntensity > second.totalIntensity
            }
            .prefix(3)
            .map { (emotion: $0.emotion, count: $0.count, dates: $0.dates) }
    }

    // MARK: - Search & Filter

    func searchBits(
        query: String = "",
        emotions: [Emotion]? = nil,
        dateRange: ClosedRange<Date>? = nil,
        intensityRange: ClosedRange<Int>? = nil,
        clusterIDs: [Int]? = nil
    ) -> [Bit] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var results: [Bit]
        if !trimmedQuery.isEmpty {
            // Retrieve results pre-ranked by hybrid BM25 + vector semantic relevance
            results = hybridSearch.search(query: trimmedQuery)
        } else {
            results = bits
        }

        // Filter by cluster
        if let clusterIDs = clusterIDs, !clusterIDs.isEmpty {
            results = results.filter { bit in
                if let id = bit.clusterID {
                    return clusterIDs.contains(id)
                }
                return false
            }
        }

        if let emotions = emotions, !emotions.isEmpty {
            results = results.filter { emotions.contains($0.emotion) }
        }

        // Date range filter
        if let dateRange = dateRange {
            results = results.filter { dateRange.contains($0.createdAt) }
        }

        // Intensity filter
        if let intensityRange = intensityRange {
            results = results.filter { intensityRange.contains($0.intensity) }
        }

        // Return results. If query is active, the caller preserves relevance order,
        // otherwise they are sorted chronologically.
        if !trimmedQuery.isEmpty {
            return results
        } else {
            return results.sorted { $0.createdAt > $1.createdAt }
        }
    }
}
