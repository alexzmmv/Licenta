//
//  SettingsView.swift
//  GJournal
//
//  Settings and account management
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repository: BaseJournalRepository
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var showingClearEmbeddingsAlert = false
    @State private var showingClearClustersAlert = false
    @State private var debugStatusMessage: String?
    @State private var isRunningDebugTask = false
    @State private var exportFileURL: URL?
    @State private var showingExportSheet = false
    @State private var isExporting = false

    @AppStorage("embeddingModelChoice") private var embeddingModelRaw: String = EmbeddingModelChoice.nomicMRL.rawValue
    @AppStorage("clusteringStrategyChoice") private var clusteringStrategyRaw: String = ClusteringStrategyChoice.classic.rawValue
    @AppStorage("debugLoggingEnabled") private var debugLoggingEnabled = false

    private var selectedModel: Binding<EmbeddingModelChoice> {
        Binding(
            get: { EmbeddingModelChoice(rawValue: embeddingModelRaw) ?? .nomicMRL },
            set: { newValue in
                embeddingModelRaw = newValue.rawValue
                EmbeddingModelChoice.current = newValue
            }
        )
    }

    private var selectedStrategy: Binding<ClusteringStrategyChoice> {
        Binding(
            get: { ClusteringStrategyChoice(rawValue: clusteringStrategyRaw) ?? .classic },
            set: { newValue in
                clusteringStrategyRaw = newValue.rawValue
                ClusteringStrategyChoice.current = newValue
            }
        )
    }

    // MARK: - AI Stats (computed from repository)

    private var totalBits: Int {
        repository.bits.filter { !$0.isDeleted }.count
    }

    private var bitsWithEmbeddings: Int {
        repository.bits.filter { !$0.isDeleted && $0.embedding != nil && !($0.embedding?.isEmpty ?? true) }.count
    }

    private var bitsWithoutEmbeddings: Int {
        totalBits - bitsWithEmbeddings
    }

    private var clusteredBits: Int {
        repository.bits.filter { !$0.isDeleted && $0.clusterID != nil }.count
    }

    private var uniqueClusterCount: Int {
        Set(repository.bits.compactMap { $0.clusterID }).count
    }

    private var noiseBits: Int {
        // Bits with embeddings but no cluster
        repository.bits.filter { !$0.isDeleted && $0.embedding != nil && !($0.embedding?.isEmpty ?? true) && $0.clusterID == nil }.count
    }

    private var embeddingDimension: Int? {
        repository.bits.first(where: { $0.embedding != nil })?.embedding?.count
    }

    private var aiManager: AIProcessingManager? {
        (repository as? LocalJournalRepository)?.aiProcessingManager
    }

    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.pink)
                        
                        VStack(alignment: .leading) {
                            Text("Account")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(authManager.currentUser ?? "Unknown")
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Account")
                }
                
                // Security Section
                Section {
                    if authManager.canUseBiometric() {
                        Toggle(isOn: Binding(
                            get: { authManager.isBiometricEnabled },
                            set: { authManager.isBiometricEnabled = $0 }
                        )) {
                            HStack {
                                Image(systemName: "faceid")
                                    .foregroundColor(.pink)
                                Text("Face ID / Touch ID")
                            }
                        }
                    } else {
                        Toggle(isOn: Binding(
                            get: { authManager.isBiometricEnabled },
                            set: { authManager.isBiometricEnabled = $0 }
                        )) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.pink)
                                Text("Require Passcode")
                            }
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text(authManager.canUseBiometric() 
                         ? "Use Face ID or Touch ID to unlock the app" 
                         : "Require device passcode to unlock the app")
                }
                
                // AI Model Section
                Section {
                    Picker(selection: selectedModel) {
                        ForEach(EmbeddingModelChoice.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.pink)
                            Text("Embedding Model")
                        }
                    }
                    Picker(selection: selectedStrategy) {
                        ForEach(ClusteringStrategyChoice.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "circle.hexagongrid.fill")
                                .foregroundColor(.purple)
                            Text("Clustering Algorithm")
                        }
                    }
                } header: {
                    Text("AI Model")
                } footer: {
                    Text("\(selectedModel.wrappedValue.subtitle)\n\(selectedStrategy.wrappedValue.subtitle)")
                }

                // MARK: - AI Pipeline Stats
                Section {
                    statsRow(icon: "doc.text", color: .blue, label: "Total Entries", value: "\(totalBits)")
                    statsRow(icon: "cpu", color: .green, label: "With Embeddings", value: "\(bitsWithEmbeddings)")
                    statsRow(icon: "exclamationmark.triangle", color: .orange, label: "Unprocessed", value: "\(bitsWithoutEmbeddings)")
                    statsRow(icon: "circle.hexagongrid", color: .purple, label: "Clusters", value: "\(uniqueClusterCount)")
                    statsRow(icon: "link", color: .cyan, label: "Clustered Entries", value: "\(clusteredBits)")
                    statsRow(icon: "waveform.path", color: .gray, label: "Noise (unclustered)", value: "\(noiseBits)")
                    if let dim = embeddingDimension {
                        statsRow(icon: "arrow.left.and.right", color: .indigo, label: "Embedding Dimensions", value: "\(dim)")
                    }
                    statsRow(icon: "gearshape.2", color: .pink, label: "Active Model", value: selectedModel.wrappedValue.displayName)
                    statsRow(icon: "circle.hexagongrid.fill", color: .purple, label: "Clustering", value: selectedStrategy.wrappedValue.displayName)
                } header: {
                    Text("AI Pipeline Stats")
                }

                // MARK: - Debug & Development
                Section {
                    // Status indicator
                    if isRunningDebugTask {
                        HStack {
                            ProgressView()
                                .tint(.pink)
                            Text(debugStatusMessage ?? "Processing…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let msg = debugStatusMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $debugLoggingEnabled) {
                        HStack {
                            Image(systemName: "terminal")
                                .foregroundColor(.orange)
                            Text("Debug Logging")
                        }
                    }

                    // Recluster All
                    Button {
                        reclusterAll()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("Recluster All Entries")
                                Text("Re-run DBSCAN on existing embeddings")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isRunningDebugTask || bitsWithEmbeddings == 0)

                    // Re-embed All
                    Button {
                        reEmbedAll()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Re-embed All Entries")
                                Text("Re-generate embeddings with current model")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isRunningDebugTask || totalBits == 0)

                    // Process Unprocessed Only
                    Button {
                        processUnprocessed()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Process Unprocessed Entries")
                                Text("Run AI pipeline on \(bitsWithoutEmbeddings) entries")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isRunningDebugTask || bitsWithoutEmbeddings == 0)

                    // Clear Embeddings
                    Button(role: .destructive) {
                        showingClearEmbeddingsAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "xmark.bin")
                            VStack(alignment: .leading) {
                                Text("Clear All Embeddings")
                                Text("Remove embedding data from all entries")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isRunningDebugTask || bitsWithEmbeddings == 0)

                    // Clear Clusters
                    Button(role: .destructive) {
                        showingClearClustersAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.3x3.topleft.filled")
                            VStack(alignment: .leading) {
                                Text("Clear All Clusters")
                                Text("Remove cluster assignments and delete cluster objects")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isRunningDebugTask || uniqueClusterCount == 0)

                    #if DEBUG
                    // Generate Seed Data
                    Button {
                        SeedDataManager.generateSeedData(context: modelContext)
                        (repository as? LocalJournalRepository)?.loadBitsFromContext()
                        debugStatusMessage = "Seed data generated"
                    } label: {
                        HStack {
                            Image(systemName: "leaf.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Generate Seed Data")
                                Text("Create sample journal entries for testing")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isRunningDebugTask)

                    // Log Embedding Sample
                    Button {
                        logEmbeddingSample()
                    } label: {
                        HStack {
                            Image(systemName: "terminal")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Log Embedding Sample")
                                Text("Print first entry's embedding to console")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(bitsWithEmbeddings == 0)
                    #endif
                } header: {
                    Text("Debug & Development")
                } footer: {
                    Text("These tools re-process entries using the currently selected embedding model.")
                }
                
                // Actions Section
                Section {
                    Button {
                        Task { await generateExportFile() }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(isExporting ? "Preparing export…" : "Export All Data")
                        }
                    }
                    .disabled(isExporting)

                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Data")
                        }
                    }

                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.square")
                            Text("Log Out")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Log Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    authManager.logout()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
            .alert("Delete All Data", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    do {
                        try modelContext.delete(model: Bit.self)
                        try modelContext.delete(model: Cluster.self)
                        try modelContext.save()
                        (repository as? LocalJournalRepository)?.aiProcessingManager?.resetState()
                        (repository as? LocalJournalRepository)?.loadBitsFromContext()
                        AppLogger.log("[Settings] Deleted all data.")
                    } catch {
                        AppLogger.error("[Settings] Failed to delete all data: \(error)")
                    }
                }
            } message: {
                Text("This will permanently delete all your journal entries. This action cannot be undone.")
            }
            .alert("Clear All Embeddings", isPresented: $showingClearEmbeddingsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear Embeddings", role: .destructive) {
                    clearAllEmbeddings()
                }
            } message: {
                Text("This will remove all AI-generated embeddings from \(bitsWithEmbeddings) entries. You can re-generate them afterwards.")
            }
            .alert("Clear All Clusters", isPresented: $showingClearClustersAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear Clusters", role: .destructive) {
                    clearAllClusters()
                }
            } message: {
                Text("This will remove all cluster assignments and delete \(uniqueClusterCount) cluster objects. You can re-cluster afterwards.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportFileURL {
                    ActivityView(items: [url])
                }
            }
        }
    }

    // MARK: - Stats Row Helper

    private func statsRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    // MARK: - Debug Actions

    private func reclusterAll() {
        guard let manager = aiManager else {
            debugStatusMessage = "AI manager not available"
            return
        }
        isRunningDebugTask = true
        debugStatusMessage = "Reclustering \(bitsWithEmbeddings) entries…"

        Task {
            do {
                try await manager.runClustering(forceRecalibrate: true)
                // onClusteringComplete already calls loadBitsFromContext — no need to repeat
                await MainActor.run {
                    debugStatusMessage = "Reclustering complete — \(uniqueClusterCount) clusters"
                    isRunningDebugTask = false
                }
            } catch {
                await MainActor.run {
                    debugStatusMessage = "Clustering failed: \(error.localizedDescription)"
                    isRunningDebugTask = false
                }
            }
        }
    }

    private func reEmbedAll() {
        guard let manager = aiManager else {
            debugStatusMessage = "AI manager not available"
            return
        }
        isRunningDebugTask = true
        debugStatusMessage = "Re-embedding \(totalBits) entries…"

        let bitsToProcess = repository.bits.filter { !$0.isDeleted }

        Task {
            var processed = 0
            for bit in bitsToProcess {
                manager.processBit(bit)
                processed += 1
                await MainActor.run {
                    debugStatusMessage = "Re-embedding… \(processed)/\(bitsToProcess.count)"
                }
                // Small delay to avoid overwhelming the system
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await MainActor.run {
                (repository as? LocalJournalRepository)?.loadBitsFromContext()
                debugStatusMessage = "Re-embedded \(processed) entries"
                isRunningDebugTask = false
            }
        }
    }

    private func processUnprocessed() {
        guard let manager = aiManager else {
            debugStatusMessage = "AI manager not available"
            return
        }
        let unprocessed = repository.bits.filter { !$0.isDeleted && !$0.hasBeenProcessed }
        guard !unprocessed.isEmpty else {
            debugStatusMessage = "All entries already processed"
            return
        }

        isRunningDebugTask = true
        debugStatusMessage = "Processing \(unprocessed.count) entries…"

        Task {
            var processed = 0
            for bit in unprocessed {
                manager.processBit(bit)
                processed += 1
                await MainActor.run {
                    debugStatusMessage = "Processing… \(processed)/\(unprocessed.count)"
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await MainActor.run {
                (repository as? LocalJournalRepository)?.loadBitsFromContext()
                debugStatusMessage = "Processed \(processed) entries"
                isRunningDebugTask = false
            }
        }
    }

    private func clearAllEmbeddings() {
        let bits = repository.bits.filter { !$0.isDeleted }
        var cleared = 0
        for bit in bits {
            if bit.embedding != nil {
                bit.embeddingData = nil
                bit.embeddingGeneratedAt = nil
                bit.flattenedText = nil
                bit.emotionProbabilitiesData = nil
                cleared += 1
            }
        }
        do {
            try modelContext.save()
            (repository as? LocalJournalRepository)?.loadBitsFromContext()
            debugStatusMessage = "Cleared embeddings from \(cleared) entries"
            AppLogger.log("[Settings] Cleared embeddings from \(cleared) entries")
        } catch {
            debugStatusMessage = "Failed to clear embeddings: \(error.localizedDescription)"
            AppLogger.error("[Settings] Failed to clear embeddings: \(error)")
        }
    }

    private func clearAllClusters() {
        let bits = repository.bits.filter { !$0.isDeleted }
        for bit in bits {
            bit.cluster = nil
            bit.clusterAssignedAt = nil
        }
        do {
            // Delete all Cluster objects
            try modelContext.delete(model: Cluster.self)
            try modelContext.save()
            (repository as? LocalJournalRepository)?.loadBitsFromContext()
            debugStatusMessage = "Cleared all cluster assignments"
            AppLogger.log("[Settings] Cleared all clusters")
        } catch {
            debugStatusMessage = "Failed to clear clusters: \(error.localizedDescription)"
            AppLogger.error("[Settings] Failed to clear clusters: \(error)")
        }
    }

    // MARK: - Export

    @MainActor
    private func generateExportFile() async {
        isExporting = true
        defer { isExporting = false }

        let iso = ISO8601DateFormatter()
        let model = EmbeddingModelChoice.current
        let strategy = ClusteringStrategyChoice.current

        // Build bits array
        var bitsJSON: [[String: Any]] = []
        for bit in repository.bits {
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
        if let cal = (repository as? LocalJournalRepository)?.aiProcessingManager?.lastCalibrationResult {
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

        let payload: [String: Any] = [
            "exportedAt": iso.string(from: Date()),
            "config": [
                "embeddingModel": model.rawValue,
                "embeddingModelDisplayName": model.displayName,
                "clusteringStrategy": strategy.rawValue,
                "clusteringStrategyDisplayName": strategy.displayName,
                "embeddingDimension": model == .nomicMRL ? 256 : 384
            ],
            "calibration": calibrationJSON,
            "summary": [
                "totalBits": repository.bits.count,
                "bitsWithEmbeddings": repository.bits.filter { $0.hasBeenProcessed }.count,
                "clusterCount": clustersJSON.count
            ],
            "clusters": clustersJSON,
            "bits": bitsJSON
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            AppLogger.error("[Settings] Export serialization failed")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let filename = "gjournal_export_\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            exportFileURL = url
            showingExportSheet = true
            AppLogger.log("[Settings] Exported \(repository.bits.count) bits to \(filename)")
        } catch {
            AppLogger.error("[Settings] Export write failed: \(error)")
        }
    }

    #if DEBUG
    private func logEmbeddingSample() {
        guard let bit = repository.bits.first(where: { $0.embedding != nil }),
              let embedding = bit.embedding else {
            debugStatusMessage = "No embeddings to log"
            return
        }
        let preview = embedding.prefix(10).map { String(format: "%.4f", $0) }.joined(separator: ", ")
        AppLogger.log("[Settings] Entry: \(bit.title ?? bit.feel.prefix(40).description)")
        AppLogger.log("[Settings] Embedding (\(embedding.count)-dim): [\(preview), ...]")
        AppLogger.log("[Settings] Generated at: \(bit.embeddingGeneratedAt?.description ?? "unknown")")
        AppLogger.log("[Settings] Cluster: \(bit.cluster?.name ?? "none") (ID: \(bit.clusterID?.description ?? "nil"))")
        if let probs = bit.emotionProbabilities {
            let sorted = probs.sorted { $0.value > $1.value }.prefix(3)
            let probStr = sorted.map { "\($0.key): \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
            AppLogger.log("[Settings] Top emotions: \(probStr)")
        }
        debugStatusMessage = "Logged embedding to console"
    }
    #endif
}

// MARK: - Share Sheet wrapper

import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView(repository: BaseJournalRepository())
        .environmentObject(AuthManager())
}
