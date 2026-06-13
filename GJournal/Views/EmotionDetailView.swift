import SwiftUI

struct EmotionDetailView: View {
    @ObservedObject var repository: BaseJournalRepository
    let emotion: Emotion
    @Environment(\.dismiss) var dismiss

    @State private var bitToEdit: Bit?
    @State private var showingDeleteAlert = false
    @State private var bitToDelete: Bit?
    @State private var bits: [Bit] = []

    private func updateData() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        self.bits = repository.bits.filter { bit in
            // Check if the emotion appears in any of the emotion fields
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
            // Dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(emotion.color.opacity(0.2))
                            .frame(width: 80, height: 80)

                        Text(emotion.emoji)
                            .font(.system(size: 40))
                    }

                    VStack(spacing: 4) {
                        Text(emotion.rawValue)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Last 30 Days")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 32)

                if bits.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.6))

                        VStack(spacing: 8) {
                            Text("No \(emotion.rawValue.lowercased()) entries")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("You haven't recorded any entries with this emotion in the last 30 days")
                                .font(.body)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    Spacer()
                } else {
                    HStack(spacing: 32) {
                        VStack(spacing: 4) {
                            Text("\(bits.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Entries")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        VStack(spacing: 4) {
                            Text("\(Set(bits.map { Calendar.current.startOfDay(for: $0.createdAt) }).count)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Days")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        VStack(spacing: 4) {
                            let avgIntensity = bits.isEmpty ? 0 : Double(bits.map { $0.intensity }.reduce(0, +)) / Double(bits.count)
                            Text(String(format: "%.1f", avgIntensity))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Avg Intensity")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.1))
                            .stroke(emotion.color.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Entries list
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
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            updateData()
        }
        .onChange(of: repository.bits) {
            updateData()
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }
            .padding(.top, 50)
            .padding(.leading, 20)
        }
        .preferredColorScheme(.dark)
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
