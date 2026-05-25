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
            VStack(alignment: .leading, spacing: 12) {
                if let title = bit.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                // Micro-journaling sections: Feel, Event, Action
                VStack(alignment: .leading, spacing: 16) {
                    // Feel section
                    if !bit.feel.isEmpty {
                        MicroJournalSection(
                            title: "Feel",
                            text: bit.feel,
                            emotion: bit.feelEmotion,
                            isHidden: bit.isHidden
                        )
                    }

                    // Event section
                    if !bit.event.isEmpty {
                        MicroJournalSection(
                            title: "Event",
                            text: bit.event,
                            emotion: bit.eventEmotion,
                            isHidden: bit.isHidden
                        )
                    }

                    // Action section
                    if !bit.action.isEmpty {
                        MicroJournalSection(
                            title: "Action",
                            text: bit.action,
                            emotion: bit.actionEmotion,
                            isHidden: bit.isHidden
                        )
                    }
                }
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
        .background(
            ZStack {
                Color.white.opacity(0.05)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
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
                feel: "I felt so peaceful watching the waves",
                event: "Went to the beach and watched a breathtaking sunset",
                action: "I want to go back next weekend with friends",
                feelEmotion: .joy,
                eventEmotion: .surprise,
                actionEmotion: .excitement,
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
                feel: "Grateful for all the love around me",
                event: "Had dinner with family",
                action: "Plan to call my grandmother this week",
                feelEmotion: .gratitude,
                eventEmotion: .joy,
                actionEmotion: .love,
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
                feel: "Conflicted and sad about the situation",
                event: "Had a difficult talk with a friend",
                action: "Need to give them space and think",
                feelEmotion: .sadness,
                eventEmotion: .anxiety,
                actionEmotion: .hope,
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

struct MicroJournalSection: View {
    let title: String
    let text: String
    let emotion: Emotion
    let isHidden: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Emotion indicator
            VStack(spacing: 4) {
                Text(emotion.emoji)
                    .font(.title2)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 60)

            // Content
            Text(text)
                .font(.body)
                .foregroundColor(isHidden ? .secondary : .primary)
                .opacity(isHidden ? 0.6 : 1)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(emotion.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(emotion.color.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
//
//  BitDetailView.swift
//  GJournal
//
//  A read-only detailed view of a single journal entry (Bit).
//

import SwiftUI

struct BitDetailView: View {
    let bit: Bit
    var clusterName: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = bit.title, !title.isEmpty {
                            Text(title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 12) {
                            Text(bit.feelEmotion.emoji)
                                .font(.title2)
                            
                            Text(bit.feelEmotion.rawValue)
                                .font(.headline)
                                .foregroundColor(bit.feelEmotion.color)

                            Spacer()

                            Text(formatDate(bit.createdAt))
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.bottom, 8)

                    // Content Sections
                    VStack(alignment: .leading, spacing: 20) {
                        detailSection(title: "How you felt", content: bit.feel)
                        
                        if !bit.event.isEmpty {
                            detailSection(title: "What happened", content: bit.event)
                        }
                        
                        if !bit.action.isEmpty {
                            detailSection(title: "What you did", content: bit.action)
                        }
                    }

                    // Metadata Section
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 8)

                        Text("Metadata")
                            .font(.headline)
                            .foregroundColor(.white)

                        metadataRow(title: "Intensity", value: String(repeating: "🔥", count: bit.intensity))
                        
                        if let clusterID = bit.clusterID, clusterID >= 0 {
                            if let name = clusterName {
                                metadataRow(title: "Cluster", value: name)
                            } else {
                                metadataRow(title: "Cluster", value: "Cluster \(clusterID)")
                            }
                        }
                        
                        metadataRow(title: "Last Modified", value: formatDateTime(bit.lastModified))
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.gray)

            Text(content)
                .font(.body)
                .foregroundColor(.white)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .cornerRadius(12)
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
