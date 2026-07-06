import SwiftUI

struct DayDetailView: View {
    @ObservedObject var repository: BaseJournalRepository
    let date: Date
    @Environment(\.dismiss) var dismiss

    @State private var showingAddBit = false
    @State private var bitToEdit: Bit?
    @State private var showingDeleteAlert = false
    @State private var bitToDelete: Bit?
    @State private var showingRepoError = false
    @State private var relatedEntries: [(bit: Bit, similarity: Float)] = []

    private var bits: [Bit] {
        repository.getBits(for: date)
    }

    private var canCreateBit: Bool {
        repository.canCreate(for: date)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today, \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, \(formatter.string(from: date))"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    private func computeRelated() {
        let dayBitIDs = Set(bits.map { $0.id })
        var all: [(bit: Bit, similarity: Float)] = []
        for dayBit in bits {
            let related = repository.hybridSearch.related(to: dayBit)
            all.append(contentsOf: related.filter { !dayBitIDs.contains($0.bit.id) })
        }
        var seen = Set<UUID>()
        relatedEntries = all
            .filter { seen.insert($0.bit.id).inserted }
            .sorted { $0.similarity > $1.similarity }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if bits.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("No bits for this day")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    if canCreateBit {
                        Text("Tap + to add your first bit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(bits) { bit in
                            BitCard(
                                bit: bit,
                                canEdit: repository.canEdit(bit: bit),
                                onEdit: { bitToEdit = bit },
                                onDelete: {
                                    bitToDelete = bit
                                    showingDeleteAlert = true
                                },
                                onToggleHide: { repository.toggleHideBit(id: bit.id) }
                            )
                        }

                        if !relatedEntries.isEmpty {
                            relatedSection
                        }
                    }
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .navigationTitle(dateString)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
            }
            if canCreateBit {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddBit = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddBit) {
            AddEditBitView(repository: repository, bitToEdit: nil, date: date)
        }
        .sheet(item: $bitToEdit) { bit in
            AddEditBitView(repository: repository, bitToEdit: bit, date: date)
        }
        .alert("Delete Bit", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { bitToDelete = nil }
            Button("Delete", role: .destructive) {
                if let bit = bitToDelete {
                    repository.deleteBit(id: bit.id)
                    bitToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this bit? This action cannot be undone.")
        }
        .onReceive(repository.$errorMessage) { new in showingRepoError = new != nil }
        .alert("Error", isPresented: $showingRepoError) {
            Button("OK") { repository.errorMessage = nil }
        } message: {
            Text(repository.errorMessage ?? "Unknown error")
        }
        .onAppear { computeRelated() }
        .onChange(of: repository.bits) { computeRelated() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Related entries section

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                Text("Related entries")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.top, 8)

            ForEach(relatedEntries, id: \.bit.id) { item in
                RelatedEntryRow(bit: item.bit, similarity: item.similarity)
            }
        }
    }
}

// MARK: - Related Entry Row

private struct RelatedEntryRow: View {
    let bit: Bit
    let similarity: Float

    private var dateLabel: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: bit.createdAt)
    }

    private var matchStrength: String {
        switch similarity {
        case 0.8...: return "Strong match"
        case 0.6...: return "Related"
        default: return "Similar"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(bit.emotion.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Text(bit.emotion.emoji).font(.title3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(bit.title ?? String(bit.feel.prefix(40)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text("\u{2022}")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(matchStrength)
                        .font(.caption2)
                        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                }
            }

            Spacer()

            Text("\(Int(similarity * 100))%")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.2), lineWidth: 1)
                )
        )
    }
}
