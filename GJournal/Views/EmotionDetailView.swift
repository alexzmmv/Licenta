import SwiftUI

struct EmotionDetailView: View {
    @ObservedObject var repository: BaseJournalRepository
    let emotion: Emotion
    @Environment(\.dismiss) var dismiss

    @State private var bitToEdit: Bit?
    @State private var showingDeleteAlert = false
    @State private var bitToDelete: Bit?

    private var bits: [Bit] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return repository.bits.filter { bit in
            bit.emotion == emotion && 
            bit.createdAt >= thirtyDaysAgo && 
            !bit.isHidden
        }
        .sorted { first, second in
            if first.isHidden != second.isHidden {
                return (first.isHidden ? 1 : 0) < (second.isHidden ? 1 : 0)
            }
            return first.lastModified > second.lastModified
        }
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            if bits.isEmpty {
                VStack(spacing: 20) {
                    Text("No entries for \(emotion.rawValue) in the last 30 days")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(bits) { bit in
                            BitCard(
                                bit: bit,
                                canEdit: repository.canEdit(bit: bit),
                                onEdit: {
                                    bitToEdit = bit
                                },
                                onDelete: {
                                    bitToDelete = bit
                                    showingDeleteAlert = true
                                },
                                onToggleHide: {
                                    repository.toggleHideBit(id: bit.id)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(emotion.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $bitToEdit) { bit in
            AddEditBitView(repository: repository, bitToEdit: bit, date: bit.createdAt)
        }
        .alert("Delete Bit", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                bitToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let bit = bitToDelete {
                    repository.deleteBit(id: bit.id)
                    bitToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this bit? This action cannot be undone.")
        }
    }
}

// Note: Preview removed as it requires authentication context
