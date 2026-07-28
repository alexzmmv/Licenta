import Foundation
import Combine
import SwiftData

class LocalJournalRepository: BaseJournalRepository {
    private var cancellables = Set<AnyCancellable>()

    var aiProcessingManager: AIProcessingManager?

    init() {
        super.init(bool: false)
    }

    override func configure(with modelContext: ModelContext) {
        super.configure(with: modelContext)
        aiProcessingManager?.configure(with: modelContext)

        aiProcessingManager?.onClusteringComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.loadBitsFromContext()
            }
        }

        // Honour the 72-hour retention promise made in RecentlyDeletedView on
        // every launch, not just while the app happens to be running.
        purgeExpiredBits()
    }
    
    // MARK: - CRUD Operations

    override func createBit(title: String?, feel: String, event: String, action: String, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        let newBit = Bit(
            id: UUID(),
            title: title,
            feel: feel,
            event: event,
            action: action,
            intensity: intensity,
            lastModified: Date(),
            createdAt: Date(),
            isHidden: false
        )

        modelContext.insert(newBit)

        do {
            try modelContext.save()
            loadBitsFromContext()
            AppLogger.log("[LocalRepository] Created micro-journal bit: \(newBit.id)")

            // Trigger background AI processing
            aiProcessingManager?.processBit(newBit)
        } catch {
            errorMessage = "Couldn't save your entry. Please try again."
            AppLogger.log("[LocalRepository] Failed to create micro-journal bit: \(error)")
        }
    }

    override func updateBit(id: UUID, title: String?, feel: String, event: String, action: String, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        if let index = bits.firstIndex(where: { $0.id == id }) {
            // The edit window is a rule, not a UI hint. Enforce it here so no
            // caller can write to an entry from a previous day.
            guard canEdit(bit: bits[index]) else {
                errorMessage = "Entries can only be edited on the day they were written."
                AppLogger.error("[LocalRepository] Rejected edit outside the allowed window: \(id)")
                return
            }

            bits[index].title = title
            bits[index].feel = feel
            bits[index].event = event
            bits[index].action = action
            bits[index].intensity = intensity
            bits[index].lastModified = Date()

            do {
                let updatedBit = bits[index]
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Updated micro-journal bit: \(id)")

                // Re-trigger AI processing for updated content (capture before reload)
                aiProcessingManager?.processBit(updatedBit)
            } catch {
                errorMessage = "Couldn't update your entry. Please try again."
                AppLogger.log("[LocalRepository] Failed to update micro-journal bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }
    
    // MARK: - Soft Delete

    override func deleteBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }
        
        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].deletedAt = Date()
            bits[index].lastModified = Date()
            
            do {
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Soft-deleted bit: \(id)")
            } catch {
                errorMessage = "Couldn't delete your entry. Please try again."
                AppLogger.log("[LocalRepository] Failed to soft-delete bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }

    override func restoreBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        let predicate = #Predicate<Bit> { $0.id == id }
        do {
            if let bit = try modelContext.fetch(FetchDescriptor<Bit>(predicate: predicate)).first {
                bit.deletedAt = nil
                bit.lastModified = Date()
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Restored bit: \(id)")
                
                // Re-trigger background AI processing to re-integrate the restored entry
                aiProcessingManager?.processBit(bit)
            } else {
                errorMessage = "Bit not found"
            }
        } catch {
            errorMessage = "Couldn't restore your entry. Please try again."
            AppLogger.log("[LocalRepository] Failed to restore bit: \(error)")
        }
    }

    override func permanentlyDeleteBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        let predicate = #Predicate<Bit> { $0.id == id }
        do {
            if let bit = try modelContext.fetch(FetchDescriptor<Bit>(predicate: predicate)).first {
                modelContext.delete(bit)
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Permanently deleted bit: \(id)")
            } else {
                errorMessage = "Bit not found"
            }
        } catch {
            errorMessage = "Couldn't permanently delete this entry. Please try again."
            AppLogger.log("[LocalRepository] Failed to permanently delete bit: \(error)")
        }
    }

    /// Permanently removes soft-deleted entries whose 72-hour retention window
    /// has elapsed. Must scan `deletedBits` — `bits` only ever holds entries
    /// with `deletedAt == nil`, for which `isPastRetention` is always false.
    func purgeExpiredBits() {
        guard let modelContext = modelContext else { return }

        let expiredBits = deletedBits.filter { $0.isPastRetention }
        guard !expiredBits.isEmpty else { return }

        for bit in expiredBits {
            modelContext.delete(bit)
        }

        do {
            try modelContext.save()
            loadBitsFromContext()
            AppLogger.log("[LocalRepository] Purged \(expiredBits.count) expired bits")
        } catch {
            AppLogger.log("[LocalRepository] Failed to purge expired bits: \(error)")
        }
    }
    
    // MARK: - Versioned JSON Export

    enum ExportError: LocalizedError {
        case contextUnavailable
        case serializationFailed

        var errorDescription: String? {
            switch self {
            case .contextUnavailable:  return "Data context not available"
            case .serializationFailed: return "Could not prepare the export file"
            }
        }
    }

    /// Current version of the export file format. Bump when the payload shape
    /// changes so future import/restore code can branch on it.
    static let exportFormatVersion = 1

    /// Builds a versioned JSON backup of all entries (including soft-deleted),
    /// clusters, and AI pipeline configuration, and writes it to a temporary
    /// file ready for the share sheet.
    func generateExportFile() throws -> URL {
        guard let modelContext = modelContext else {
            throw ExportError.contextUnavailable
        }

        let iso = ISO8601DateFormatter()
        let model = EmbeddingModelChoice.current
        let strategy = ClusteringStrategyChoice.current

        var bitsJSON: [[String: Any]] = []
        for bit in bits {
            var entry: [String: Any] = [
                "id": bit.id.uuidString,
                "feel": bit.feel,
                "event": bit.event,
                "action": bit.action,
                "intensity": bit.intensity,
                "emotion": bit.emotion.rawValue,
                "isHidden": bit.isHidden,
                "isDeleted": bit.isDeleted,
                "hasBeenProcessed": bit.hasBeenProcessed,
                "createdAt": iso.string(from: bit.createdAt),
                "lastModified": iso.string(from: bit.lastModified)
            ]
            if let title = bit.title { entry["title"] = title }
            if let clusterIndex = bit.clusterID {
                entry["clusterIndex"] = clusterIndex
                entry["clusterName"] = bit.cluster?.name ?? ""
            }
            if let probs = bit.emotionProbabilities {
                entry["emotionProbabilities"] = probs
            }
            if let emb = bit.embedding {
                entry["embedding"] = emb
                entry["embeddingDim"] = emb.count
            }
            if let t = bit.flattenedText { entry["flattenedText"] = t }
            if let d = bit.embeddingGeneratedAt { entry["embeddingGeneratedAt"] = iso.string(from: d) }
            bitsJSON.append(entry)
        }

        // Fetch clusters directly from context for complete picture
        var clustersJSON: [[String: Any]] = []
        let allClusters = (try? modelContext.fetch(FetchDescriptor<Cluster>())) ?? []
        for c in allClusters {
            clustersJSON.append([
                "index": c.index,
                "name": c.name,
                "bitCount": c.bits.filter { !$0.isDeleted }.count,
                "createdAt": iso.string(from: c.createdAt)
            ])
        }

        // Build calibration diagnostics (if available)
        var calibrationJSON: [String: Any] = [:]
        if let cal = aiProcessingManager?.lastCalibrationResult {
            calibrationJSON = [
                "epsilon": cal.epsilon,
                "minPoints": cal.minPoints,
                "clusterCount": cal.clusterCount,
                "noiseCount": cal.noiseCount,
                "totalPoints": cal.totalPoints,
                "noiseFraction": cal.noiseFraction,
                "silhouetteScore": cal.silhouetteScore
            ]
        }

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

        let payload: [String: Any] = [
            "formatVersion": Self.exportFormatVersion,
            "schemaVersion": "\(SchemaV1.versionIdentifier)",
            "appVersion": appVersion,
            "exportedAt": iso.string(from: Date()),
            "config": [
                "embeddingModel": model.rawValue,
                "embeddingModelDisplayName": model.displayName,
                "clusteringStrategy": strategy.rawValue,
                "clusteringStrategyDisplayName": strategy.displayName,
                "embeddingDimension": model.embeddingDimension
            ],
            "calibration": calibrationJSON,
            "summary": [
                "totalBits": bits.count,
                "bitsWithEmbeddings": bits.filter { $0.hasBeenProcessed }.count,
                "clusterCount": clustersJSON.count
            ],
            "clusters": clustersJSON,
            "bits": bitsJSON
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            AppLogger.error("[LocalRepository] Export serialization failed")
            throw ExportError.serializationFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let filename = "gjournal_export_\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try data.write(to: url, options: .atomic)
        // Protect the export file so it is inaccessible while the device is locked
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
        AppLogger.log("[LocalRepository] Exported \(bits.count) bits to \(filename)")
        return url
    }

    override func toggleHideBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].isHidden.toggle()
            bits[index].lastModified = Date()

            do {
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Toggled hide for bit: \(id)")
            } catch {
                errorMessage = "Couldn't update visibility. Please try again."
                AppLogger.log("[LocalRepository] Failed to toggle bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }
}

// MARK: - Seed Data Generation

struct SeedDataManager {

    // MARK: - JSON model

    private struct SeedFile: Decodable {
        let entries: [SeedEntry]
    }

    private struct SeedEntry: Decodable {
        let title: String
        let feel: String
        let event: String
        let action: String
        let intensity: Int
        let daysAgo: Int
    }

    // MARK: - Loading

    @MainActor
    static func generateSeedData(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "seed_data", withExtension: "json") else {
            AppLogger.log("[SeedData] seed_data.json not found in bundle.")
            return
        }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SeedFile.self, from: data) else {
            AppLogger.log("[SeedData] Failed to decode seed_data.json.")
            return
        }

        let now = Date()
        let calendar = Calendar.current

        for entry in file.entries {
            let entryDate = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) ?? now
            let bit = Bit(
                id: UUID(),
                title: entry.title,
                feel: entry.feel,
                event: entry.event,
                action: entry.action,
                intensity: min(max(entry.intensity, 1), 4),
                lastModified: entryDate,
                createdAt: entryDate,
                isHidden: false
            )
            context.insert(bit)
        }

        do {
            try context.save()
            AppLogger.log("[SeedData] Inserted \(file.entries.count) unclustered entries.")
        } catch {
            AppLogger.log("[SeedData] Failed to save: \(error)")
        }
    }
}
