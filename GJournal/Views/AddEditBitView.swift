//
//  AddEditBitView.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import SwiftUI

struct AddEditBitView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repository: BaseJournalRepository
    @FocusState private var focusedField: Field?

    let bitToEdit: Bit?
    let date: Date

    @State private var title: String = ""
    @State private var text: String = ""
    @State private var selectedEmotion: Emotion = .joy
    @State private var intensity: Int = 2
    @State private var showingRepoError = false

    enum Field {
        case title
        case text
    }

    var isEditing: Bool {
        bitToEdit != nil
    }

    var viewTitle: String {
        isEditing ? "Edit Bit" : "Add Bit"
    }

    private let intensityLabels = ["Mild", "Moderate", "Strong", "Intense"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Title field (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("Give your entry a title...", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .focused($focusedField, equals: .title)
                    }

                    // Text input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How are you feeling?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(uiColor: .systemGray4), lineWidth: 0.5)
                            )
                            .focused($focusedField, equals: .text)
                    }

                    // Emotion selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What emotion best describes this?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(Emotion.allCases, id: \.self) { emotion in
                                EmotionPill(
                                    emotion: emotion,
                                    isSelected: selectedEmotion == emotion
                                ) {
                                    focusedField = nil // Dismiss keyboard
                                    selectedEmotion = emotion
                                }
                            }
                        }
                    }

                    // Intensity selector
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How intense is this feeling?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 0) {
                            ForEach(1...4, id: \.self) { level in
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(level == intensity ? selectedEmotion.color : Color(uiColor: .secondarySystemGroupedBackground))
                                            .frame(width: 60, height: 60)

                                        Circle()
                                            .stroke(Color(uiColor: .systemGray4), lineWidth: level == intensity ? 0 : 1)
                                            .frame(width: 60, height: 60)

                                        if level == intensity {
                                            Circle()
                                                .fill(Color(uiColor: .systemBackground))
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                    .onTapGesture {
                                        focusedField = nil // Dismiss keyboard
                                        intensity = level
                                    }

                                    Text(intensityLabels[level - 1])
                                        .font(.caption)
                                        .foregroundColor(level == intensity ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    // Save button
                    Button(action: {
                        saveBit()
                        dismiss()
                    }) {
                        Text("Save Entry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedEmotion.color.opacity(0.8))
                            .cornerRadius(12)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .padding(24)
            }
            .navigationTitle(viewTitle)
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
        }
        .onAppear {
            if let bit = bitToEdit {
                title = bit.title ?? ""
                text = bit.text
                selectedEmotion = bit.emotion
                intensity = bit.intensity
            }
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

    private func saveBit() {
        let titleToSave = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
        if let bit = bitToEdit {
            repository.updateBit(id: bit.id, title: titleToSave, text: text, emotion: selectedEmotion, intensity: intensity)
        } else {
            repository.createBit(title: titleToSave, text: text, emotion: selectedEmotion, intensity: intensity)
        }
    }
}

struct EmotionPill: View {
    let emotion: Emotion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emotion.emoji)
                    .font(.body)
                Text(emotion.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? emotion.color.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? emotion.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
