#if DEBUG
import SwiftUI
import SwiftData

/// Developer-only tools: model/strategy pickers, pipeline maintenance actions,
/// and the thesis efficiency benchmark. The entire file is compiled out of
/// Release builds — none of these destructive tools can ship to users.
struct DebugSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var repository: BaseJournalRepository

    @State private var showingClearEmbeddingsAlert = false
    @State private var showingClearClustersAlert = false
    @State private var debugStatusMessage: String?
    @State private var isRunningDebugTask = false
    @State private var isBenchmarking = false
    @State private var benchmarkStatusMessage: String?
    @State private var exportFileURL: URL?
    @State private var showingExportSheet = false
    @State private var showingCrisisResources = false

    @AppStorage("embeddingModelChoice") private var embeddingModelRaw: String = EmbeddingModelChoice.miniLM.rawValue
    @AppStorage("clusteringStrategyChoice") private var clusteringStrategyRaw: String = ClusteringStrategyChoice.classic.rawValue
    @AppStorage("debugLoggingEnabled") private var debugLoggingEnabled = false

    @Environment(EntitlementManager.self) private var entitlementManager
    @AppStorage("bypassPaywall") private var bypassPaywall = false

    private var selectedModel: Binding<EmbeddingModelChoice> {
        Binding(
            get: { EmbeddingModelChoice(rawValue: embeddingModelRaw) ?? .miniLM },
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

    private var totalBits: Int {
        repository.bits.filter { !$0.isDeleted }.count
    }

    private var bitsWithEmbeddings: Int {
        repository.bits.filter { !$0.isDeleted && $0.embedding != nil && !($0.embedding?.isEmpty ?? true) }.count
    }

    private var bitsWithoutEmbeddings: Int {
        totalBits - bitsWithEmbeddings
    }

    private var uniqueClusterCount: Int {
        Set(repository.bits.compactMap { $0.clusterID }).count
    }

    private var aiManager: AIProcessingManager? {
        (repository as? LocalJournalRepository)?.aiProcessingManager
    }

    var body: some View {
        List {
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

            Section {
                Toggle(isOn: $bypassPaywall) {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(.green)
                        Text("Bypass Paywall (Force Paid)")
                    }
                }
                .onChange(of: bypassPaywall) { _, newValue in
                    Task {
                        await entitlementManager.refreshEntitlements()
                    }
                }
            } header: {
                Text("Licensing & Paywall Override")
            } footer: {
                Text("When enabled, all premium features (Network Graphs, Trajectories, and Advanced Insights) will be immediately unlocked and treated as purchased.")
            }

            Section {
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
            } header: {
                Text("Debug & Development")
            } footer: {
                Text("These tools re-process entries using the currently selected embedding model.")
            }

            Section {
                if isBenchmarking {
                    HStack {
                        ProgressView().tint(.orange)
                        Text(benchmarkStatusMessage ?? "Running…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let msg = benchmarkStatusMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    Task { await runEfficiencyBenchmark() }
                } label: {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Run Efficiency Benchmark")
                            Text("Cold start + 50 warm runs per model — exports JSON")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isBenchmarking)
            } header: {
                Text("Thesis Benchmark")
            }

            Section {
                // Notification triggers
                Button {
                    triggerTestNotification()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading) {
                            Text("Trigger Test Notification (5s)")
                            Text("Schedules a daily reminder after a 5s delay")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    printPendingNotifications()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Print Pending Notifications")
                            Text("Print scheduled alerts to log console")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    cancelAllNotifications()
                } label: {
                    HStack {
                        Image(systemName: "bell.slash")
                            .foregroundColor(.red)
                        VStack(alignment: .leading) {
                            Text("Cancel All Notifications")
                            Text("Removes all pending notifications")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Crash triggers
                Button(role: .destructive) {
                    forceAppCrash()
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        VStack(alignment: .leading) {
                            Text("Force App Crash")
                            Text("Immediately crash the app with fatalError")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    generateMockCrashReport()
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Generate Mock Crash Report")
                            Text("Writes a dummy MetricKit payload to disk")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    clearSavedCrashReports()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        VStack(alignment: .leading) {
                            Text("Clear Saved Crash Reports")
                            Text("Deletes all files in CrashReports directory")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Safety trigger
                Button {
                    showingCrisisResources = true
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square")
                            .foregroundColor(.red)
                        VStack(alignment: .leading) {
                            Text("Simulate Self-Harm Warning")
                            Text("Triggers the Crisis Resources sheet immediately")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Tag processor & Insight Engine triggers
                Button {
                    runTagBackfill()
                } label: {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Force Tag Processor Backfill")
                            Text("Extracts and canonicalizes tags for all entries")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isRunningDebugTask)

                Button {
                    runManualInsightEngine()
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Run Insight Engine Analysis")
                            Text("Re-runs GGM Psychological Network analysis")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isRunningDebugTask)
            } header: {
                Text("Manual Diagnostic Triggers")
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showingCrisisResources) {
            CrisisResourcesView()
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
                // Small delay to avoid "burnout"
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
            AppLogger.log("[Debug] Cleared embeddings from \(cleared) entries")
        } catch {
            debugStatusMessage = "Failed to clear embeddings: \(error.localizedDescription)"
            AppLogger.error("[Debug] Failed to clear embeddings: \(error)")
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
            AppLogger.log("[Debug] Cleared all clusters")
        } catch {
            debugStatusMessage = "Failed to clear clusters: \(error.localizedDescription)"
            AppLogger.error("[Debug] Failed to clear clusters: \(error)")
        }
    }

    private func logEmbeddingSample() {
        guard let bit = repository.bits.first(where: { $0.embedding != nil }),
              let embedding = bit.embedding else {
            debugStatusMessage = "No embeddings to log"
            return
        }
        let preview = embedding.prefix(10).map { String(format: "%.4f", $0) }.joined(separator: ", ")
        AppLogger.log("[Debug] Entry: \(bit.title ?? bit.feel.prefix(40).description)")
        AppLogger.log("[Debug] Embedding (\(embedding.count)-dim): [\(preview), ...]")
        AppLogger.log("[Debug] Generated at: \(bit.embeddingGeneratedAt?.description ?? "unknown")")
        AppLogger.log("[Debug] Cluster: \(bit.cluster?.name ?? "none") (ID: \(bit.clusterID?.description ?? "nil"))")
        if let probs = bit.emotionProbabilities {
            let sorted = probs.sorted { $0.value > $1.value }.prefix(3)
            let probStr = sorted.map { "\($0.key): \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
            AppLogger.log("[Debug] Top emotions: \(probStr)")
        }
        debugStatusMessage = "Logged embedding to console"
    }

    // MARK: - Thesis Benchmark

    private func runEfficiencyBenchmark() async {
        isBenchmarking = true
        benchmarkStatusMessage = "Starting…"
        do {
            let report = try await EfficiencyBenchmark().run { msg in
                await MainActor.run { self.benchmarkStatusMessage = msg }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm"
            let filename = "gjournal_benchmark_\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            exportFileURL = url
            showingExportSheet = true
            benchmarkStatusMessage = "Done — \(report.embeddings.count) models benchmarked"
            isBenchmarking = false
        } catch {
            benchmarkStatusMessage = "Failed: \(error.localizedDescription)"
            isBenchmarking = false
        }
    }

    private func triggerTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "A moment for yourself"
        content.body = "How are you feeling today? Your journal is waiting."
        content.sound = .default
        content.interruptionLevel = .passive
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "gjournal.test.reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error = error {
                    debugStatusMessage = "Notification failed: \(error.localizedDescription)"
                } else {
                    debugStatusMessage = "Test notification scheduled (5s)"
                }
            }
        }
    }

    private func printPendingNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let summary = requests.map { "\($0.identifier): \($0.content.title)" }.joined(separator: ", ")
            Task { @MainActor in
                debugStatusMessage = requests.isEmpty ? "No pending notifications" : "Pending: \(summary)"
                AppLogger.log("[Debug] Pending notification requests: \(summary)")
            }
        }
    }

    private func cancelAllNotifications() {
        ReminderScheduler.shared.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["gjournal.test.reminder"])
        debugStatusMessage = "All notifications cancelled"
    }

    private func forceAppCrash() {
        fatalError("Developer triggered deliberate crash for testing CrashReporter")
    }

    private func generateMockCrashReport() {
        guard let dir = CrashReporter.reportsDirectory else {
            debugStatusMessage = "Error accessing reports directory"
            return
        }
        let fm = FileManager.default
        let stamp = UInt(Date().timeIntervalSince1970)
        let fileURL = dir.appendingPathComponent("diagnostic-\(stamp)-mock.json")
        
        // A mock payload to simulate standard crash report metadata
        let mockJSON = """
        {
          "crashDiagnostics": [
            {
              "signal": 11,
              "exceptionType": 1,
              "exceptionCode": 0,
              "terminationReason": "NAMESPACE=SIGNAL CODE=0x0b",
              "virtualMemoryAddress": 0
            }
          ],
          "timeStampBegin": "2026-07-11T12:00:00Z",
          "timeStampEnd": "2026-07-11T12:05:00Z"
        }
        """
        do {
            try mockJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            debugStatusMessage = "Generated mock report on disk"
            AppLogger.log("[Debug] Persisted mock diagnostic payload to \(fileURL.lastPathComponent)")
        } catch {
            debugStatusMessage = "Failed to generate mock: \(error.localizedDescription)"
        }
    }

    private func clearSavedCrashReports() {
        guard let dir = CrashReporter.reportsDirectory else {
            debugStatusMessage = "Error accessing reports directory"
            return
        }
        let fm = FileManager.default
        do {
            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for file in files {
                try fm.removeItem(at: file)
            }
            debugStatusMessage = "Cleared \(files.count) reports"
            AppLogger.log("[Debug] Cleared saved crash reports")
        } catch {
            debugStatusMessage = "Failed to clear reports: \(error.localizedDescription)"
        }
    }

    private func runTagBackfill() {
        guard let manager = aiManager else {
            debugStatusMessage = "AI manager not available"
            return
        }
        isRunningDebugTask = true
        debugStatusMessage = "Starting tag backfill..."
        Task {
            await manager.backfillTags { done, total in
                Task { @MainActor in
                    debugStatusMessage = "Backfilled tags: \(done)/\(total)"
                    if done == total {
                        isRunningDebugTask = false
                        (repository as? LocalJournalRepository)?.loadBitsFromContext()
                    }
                }
            }
        }
    }

    private func runManualInsightEngine() {
        isRunningDebugTask = true
        debugStatusMessage = "Running Insight Engine..."
        Task {
            let tags = (try? modelContext.fetch(FetchDescriptor<BehavioralTag>())) ?? []
            let engine = InsightEngine()
            await engine.compute(bits: repository.bits, allTags: tags)
            await MainActor.run {
                if let net = engine.network {
                    debugStatusMessage = "Insight Engine complete — \(net.edges.count) edges"
                } else {
                    debugStatusMessage = "Insight Engine: no network generated"
                }
                isRunningDebugTask = false
            }
        }
    }
}
#endif

