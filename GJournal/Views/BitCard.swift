//  BitCard.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import SwiftUI

struct BitCard: View {
    let bit: Bit
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleHide: () -> Void
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with emoji and menu
            HStack {
                Text(bit.emotion.emoji)
                    .font(.title)
                Text(bit.emotion.rawValue.capitalized)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Menu {
                    if canEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    
                    Button {
                        onToggleHide()
                    } label: {
                        Label(bit.isHidden ? "Show" : "Hide", systemImage: bit.isHidden ? "eye" : "eye.slash")
                    }
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                if let title = bit.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text(bit.text)
                    .font(.body)
                    .foregroundColor(bit.isHidden ? .secondary : .primary)
                    .opacity(bit.isHidden ? 0.6 : 1)
                    .lineLimit(nil)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Footer with time and intensity
            HStack {
                Text(formattedTime(bit.lastModified))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Intensity")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 3) {
                        ForEach(1...4, id: \.self) { level in
                            Circle()
                                .fill(level <= bit.intensity ? bit.emotion.color : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .opacity(bit.isHidden ? 0.45 : 1)
    }
}

#Preview {
    VStack(spacing: 16) {
        // Card with title
        BitCard(
            bit: Bit(
                id: UUID(),
                title: "Amazing Day at the Beach",
                text: "Today was incredible! The sunset was breathtaking and I felt so peaceful watching the waves.",
                emotion: .joy,
                intensity: 4,
                lastModified: Date(),
                isHidden: false
            ),
            canEdit: true,
            onEdit: {},
            onDelete: {},
            onToggleHide: {}
        )
        
        // Card without title
        BitCard(
            bit: Bit(
                id: UUID(),
                title: nil,
                text: "Feeling grateful for my family and friends today.",
                emotion: .gratitude,
                intensity: 3,
                lastModified: Date(),
                isHidden: false
            ),
            canEdit: true,
            onEdit: {},
            onDelete: {},
            onToggleHide: {}
        )
        
        // Hidden card
        BitCard(
            bit: Bit(
                id: UUID(),
                title: "Tough Conversation",
                text: "Had a difficult talk with a friend. Feeling conflicted about the situation.",
                emotion: .sadness,
                intensity: 2,
                lastModified: Date(),
                isHidden: true
            ),
            canEdit: false,
            onEdit: {},
            onDelete: {},
            onToggleHide: {}
        )
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
