//
//  DayDetailView.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

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

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

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
        .navigationTitle(dateString)
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

            if canCreateBit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddBit = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
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
        .onReceive(repository.$errorMessage) { new in
            showingRepoError = new != nil
        }
        .alert("Error", isPresented: $showingRepoError) {
            Button("OK") {
                repository.errorMessage = nil
            }
        } message: {
            Text(repository.errorMessage ?? "Unknown error")
        }
    }
}
