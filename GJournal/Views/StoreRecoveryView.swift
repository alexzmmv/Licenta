import SwiftUI

/// Shown when the SwiftData store fails to open (e.g., schema migration error).
///
/// This replaces the previous behavior of silently wiping and recreating the store.
/// The user's journal data is preserved on disk; this view offers options to retry
/// or export the raw database files for safekeeping.
struct StoreRecoveryView: View {
    let error: Error

    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                // Headline
                Text("Unable to Open Journal")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                // Explanation
                Text("GJournal couldn't open your data store. This can happen after an app update changes the data format.\n\nYour journals are safe on disk — they have **not** been deleted.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Actions
                VStack(spacing: 12) {
                    Button {
                        // Ask the user to manually close and reopen the app.
                        // We avoid calling exit(0) because Apple discourages
                        // programmatic termination and it may cause App Review issues.
                        showRetryInstructions = true
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("storeRecovery_retry")

                    Button {
                        exportRawStore()
                    } label: {
                        Label("Export Database Files", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("storeRecovery_export")
                }
                .padding(.horizontal, 40)

                // Error detail (collapsible)
                GroupBox {
                    Text(error.localizedDescription)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } label: {
                    Label("Technical Details", systemImage: "info.circle")
                        .font(.caption.bold())
                }
                .padding(.horizontal)

                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemBackground))
        .alert("Close & Reopen", isPresented: $showRetryInstructions) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please swipe up to close GJournal from the app switcher, then reopen it. The app will try to load your data again.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if !exportURLs.isEmpty {
                StoreRecoveryShareSheet(activityItems: exportURLs)
            }
        }
    }

    @State private var showRetryInstructions = false

    // MARK: - Export

    private func exportRawStore() {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        let storeURL = config.url
        let dir = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent

        // Collect all store-related files (main DB + WAL + SHM)
        let suffixes = ["", "-wal", "-shm"]
        var sourceFiles: [URL] = []
        for suffix in suffixes {
            let fileURL = dir.appendingPathComponent(name + suffix)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                sourceFiles.append(fileURL)
            }
        }

        guard !sourceFiles.isEmpty else {
            exportError = "No database files found at expected location."
            return
        }

        // Copy to a temporary directory so the share sheet can access them safely
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GJournal-Recovery-\(timestamp)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            var copied: [URL] = []
            for file in sourceFiles {
                let dest = tempDir.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: dest)
                copied.append(dest)
            }
            exportURLs = copied
            exportError = nil
            showingShareSheet = true
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - UIKit Share Sheet Wrapper

/// Thin UIViewControllerRepresentable wrapper for UIActivityViewController.
/// Used here because ShareLink doesn't handle dynamically-generated file arrays well.
private struct StoreRecoveryShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
