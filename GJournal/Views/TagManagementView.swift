import SwiftUI
import SwiftData

/// Behavioral-tag management (plan §2.0): review the mined tags, delete junk, and run the
/// one-shot backfill for entries created before tagging existed. Mitigates junk-tag risk and
/// keeps the GGM variables clean.
struct TagManagementView: View {
    @ObservedObject var repository: BaseJournalRepository
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BehavioralTag.count, order: .reverse)])
    private var tags: [BehavioralTag]

    @State private var isBackfilling = false
    @State private var backfillProgress: (done: Int, total: Int)?

    private var aiManager: AIProcessingManager? {
        (repository as? LocalJournalRepository)?.aiProcessingManager
    }

    var body: some View {
        List {
            Section {
                backfillRow
            } footer: {
                Text("Tags are mined from your Event and Action text on-device. A tag joins your psychological network once it appears \(BehavioralTag.ggmThreshold)+ times.")
            }

            if !tags.isEmpty {
                Section("Event tags") { tagRows(category: .event) }
                Section("Action tags") { tagRows(category: .action) }
            }
        }
        .navigationTitle("Behavioral Tags")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func tagRows(category: TagCategory) -> some View {
        let filtered = tags.filter { $0.category == category }
        if filtered.isEmpty {
            Text("None yet").foregroundColor(.gray).font(.subheadline)
        } else {
            ForEach(filtered) { tag in
                HStack {
                    Text(tag.lemma.capitalized)
                    if tag.isGGMEligible {
                        Text("in network")
                            .font(.caption2).foregroundColor(.purple)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15)).clipShape(Capsule())
                    }
                    Spacer()
                    Text("\(tag.count)×").foregroundColor(.gray).font(.subheadline)
                }
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(filtered[i]) }
                try? modelContext.save()
            }
        }
    }

    private var backfillRow: some View {
        Button {
            guard !isBackfilling else { return }
            isBackfilling = true
            Task {
                await aiManager?.backfillTags { done, total in
                    backfillProgress = (done, total)
                }
                isBackfilling = false
            }
        } label: {
            HStack {
                Label("Backfill tags for older entries", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if isBackfilling {
                    if let p = backfillProgress, p.total > 0 {
                        Text("\(p.done)/\(p.total)").foregroundColor(.gray).font(.caption)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .disabled(isBackfilling || aiManager == nil)
    }
}
