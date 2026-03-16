//
//  BaseJournalRepository.swift
//  GJournal
//
//  Base repository protocol implementation
//

import Foundation
import Combine
import SwiftData

open class BaseJournalRepository: ObservableObject {
    @Published var bits: [Bit] = []
    @Published var errorMessage: String? = nil
    
    var modelContext: ModelContext?

    init(bool loadSampleDataInit: Bool = false) {
        // Subclasses should override to implement their own loading
    }
    
    open func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadBitsFromContext()
    }
    
    open func loadBitsFromContext() {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<Bit>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        
        do {
            bits = try modelContext.fetch(descriptor)
            print("[Repository] Loaded \(bits.count) bits from SwiftData")
        } catch {
            print("[Repository] Failed to load bits: \(error)")
            bits = []
        }
    }

    // MARK: - CRUD operations (override in subclasses)

    func createBit(title: String?, text: String, emotion: Emotion, intensity: Int) {
        // Override in subclass
    }

    func updateBit(id: UUID, title: String?, text: String, emotion: Emotion, intensity: Int) {
        // Override in subclass
    }

    func deleteBit(id: UUID) {
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
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let bitDay = calendar.startOfDay(for: bit.createdAt)

        return bitDay == today || bitDay == yesterday
    }

    func canCreate(for date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.isDateInToday(date)
    }

    func getTopEmotionsLastMonth() -> [(emotion: Emotion, count: Int, dates: [Date])] {
        let calendar = Calendar.current
        let now = Date()
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!

        let recentBits = bits.filter { $0.createdAt >= monthAgo && $0.createdAt <= now && !$0.isHidden }

        var emotionData: [Emotion: (dates: [Date], totalIntensity: Int)] = [:]
        for bit in recentBits {
            let day = calendar.startOfDay(for: bit.createdAt)
            if var data = emotionData[bit.emotion] {
                data.dates.append(day)
                data.totalIntensity += bit.intensity
                emotionData[bit.emotion] = data
            } else {
                emotionData[bit.emotion] = (dates: [day], totalIntensity: bit.intensity)
            }
        }

        return emotionData
            .map { (emotion: $0.key, count: $0.value.dates.count, dates: Array(Set($0.value.dates)).sorted(), totalIntensity: $0.value.totalIntensity) }
            .sorted { first, second in
                if first.count != second.count {
                    return first.count > second.count
                }
                return first.totalIntensity > second.totalIntensity
            }
            .prefix(3)
            .map { (emotion: $0.emotion, count: $0.count, dates: $0.dates) }
    }
}
