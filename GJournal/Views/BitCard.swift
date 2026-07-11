import SwiftUI

struct BitCard: View {
    let bit: Bit
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleHide: () -> Void
    var onClusterTap: ((Int) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            
            VStack(alignment: .leading, spacing: 12) {
                if let title = bit.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if !bit.feel.isEmpty {
                        MicroJournalSection(title: "Feel", text: bit.feel, isHidden: bit.isHidden)
                    }
                    if !bit.event.isEmpty {
                        MicroJournalSection(title: "Event", text: bit.event, isHidden: bit.isHidden)
                    }
                    if !bit.action.isEmpty {
                        MicroJournalSection(title: "Action", text: bit.action, isHidden: bit.isHidden)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            HStack {
                Text(bit.lastModified.timeOfDay)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let clusterID = bit.clusterID, clusterID >= 0 {
                    Button {
                        onClusterTap?(clusterID)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "circle.grid.hex.fill")
                                .font(.system(size: 8))
                            Text(bit.cluster?.displayName ?? "Cluster \(clusterID)")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.12))
                        .cornerRadius(8)
                        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                    }
                    .buttonStyle(.plain)
                }
                
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
        .glassCard(cornerRadius: 16)
        .opacity(bit.isHidden ? 0.45 : 1)
    }
}

#Preview {
    VStack(spacing: 16) {
        BitCard(
            bit: Bit(
                title: "Amazing Day at the Beach",
                feel: "I felt so peaceful watching the waves",
                event: "Went to the beach and watched a breathtaking sunset",
                action: "I want to go back next weekend with friends",
                intensity: 4,
                lastModified: Date()
            ),
            canEdit: true, onEdit: {}, onDelete: {}, onToggleHide: {}
        )
        BitCard(
            bit: Bit(
                feel: "Grateful for all the love around me",
                event: "Had dinner with family",
                action: "Plan to call my grandmother this week",
                intensity: 3,
                lastModified: Date()
            ),
            canEdit: true, onEdit: {}, onDelete: {}, onToggleHide: {}
        )
        BitCard(
            bit: Bit(
                title: "Tough Conversation",
                feel: "Conflicted and sad about the situation",
                event: "Had a difficult talk with a friend",
                action: "Need to give them space and think",
                intensity: 2,
                lastModified: Date(),
                isHidden: true
            ),
            canEdit: false, onEdit: {}, onDelete: {}, onToggleHide: {}
        )
    }
    .padding()
    .background(Color.black)
}

struct MicroJournalSection: View {
    let title: String
    let text: String
    let isHidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.8)

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
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

import SwiftUI

struct BitDetailView: View {
    @State private var currentBit: Bit
    var clusterName: String?
    var allBits: [Bit] = []
    @Environment(\.dismiss) var dismiss
    var onClusterTap: ((Int) -> Void)? = nil

    init(bit: Bit, clusterName: String? = nil, allBits: [Bit] = [], onClusterTap: ((Int) -> Void)? = nil) {
        _currentBit = State(initialValue: bit)
        self.clusterName = clusterName
        self.allBits = allBits
        self.onClusterTap = onClusterTap
    }

    private var clusterSpanLabel: String? {
        guard let cluster = currentBit.cluster else { return nil }
        let dates = cluster.bits.filter { !$0.isDeleted }.map { $0.createdAt }
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lo, to: hi).day ?? 0
        guard days > 1 else { return nil }
        if days < 30 { return "\(days) days" }
        let months = Int(round(Double(days) / 30.0))
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return "\(f.string(from: lo)) – \(f.string(from: hi)) (\(months) months)"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = currentBit.title, !title.isEmpty {
                            Text(title)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 12) {
                            Text(currentBit.emotion.emoji)
                                .font(.title2)

                            Text(currentBit.emotion.rawValue)
                                .font(.headline)
                                .foregroundColor(currentBit.emotion.color)

                            Spacer()

                            Text(formatDate(currentBit.createdAt))
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 20) {
                        detailSection(title: "How you felt", content: currentBit.feel)

                        if !currentBit.event.isEmpty {
                            detailSection(title: "What happened", content: currentBit.event)
                        }

                        if !currentBit.action.isEmpty {
                            detailSection(title: "What you did", content: currentBit.action)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 8)

                        Text("Metadata")
                            .font(.headline)
                            .foregroundColor(.white)

                        metadataRow(title: "Intensity", value: String(repeating: "🔥", count: currentBit.intensity))

                        if let clusterID = currentBit.clusterID, clusterID >= 0 {
                            Button {
                                onClusterTap?(clusterID)
                            } label: {
                                HStack {
                                    Text("Cluster")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text(clusterName ?? "Cluster \(clusterID)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if let spanLabel = clusterSpanLabel {
                            metadataRow(title: "Cluster span", value: spanLabel)
                        }

                        metadataRow(title: "Last Modified", value: formatDateTime(currentBit.lastModified))
                    }
                    .padding(.top, 8)

                    let pool = allBits.isEmpty
                        ? (currentBit.cluster?.bits.filter { !$0.isDeleted && $0.id != currentBit.id } ?? [])
                        : allBits.filter { !$0.isDeleted && $0.id != currentBit.id }
                    let connected = SemanticUtils.relatedBits(to: currentBit, in: pool, limit: 3)
                        .filter { $0.similarity >= 0.45 }
                    if !connected.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.vertical, 8)

                            Text("Connected moments")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(connected, id: \.bit.id) { item in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentBit = item.bit
                                    }
                                } label: {
                                    ConnectedMomentRow(bit: item.bit, similarity: item.similarity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(20)
                .id(currentBit.id)
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

// MARK: - Connected Moment Row

struct ConnectedMomentRow: View {
    let bit: Bit
    let similarity: Float

    private var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: bit.createdAt)
    }

    private var similarityDots: Int {
        switch similarity {
        case 0.85...: return 3
        case 0.72...: return 2
        default:      return 1
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(bit.emotion.emoji).font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(bit.feel.isEmpty ? bit.event : bit.feel)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(dateLabel)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            HStack(spacing: 3) {
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .fill(i <= similarityDots ? bit.emotion.color : Color.white.opacity(0.12))
                        .frame(width: 6, height: 6)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
        .cornerRadius(10)
    }
}
