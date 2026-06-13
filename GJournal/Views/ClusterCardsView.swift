import SwiftUI

struct ClusterCardsView: View {
    @ObservedObject var repository: BaseJournalRepository
    @State private var selectedCluster: Cluster?

    private var clusters: [Cluster] {
        let all = repository.bits
            .compactMap { $0.cluster }
            .uniqued()
            .filter { $0.index >= 0 }
        return all.sorted {
            ($0.bits.compactMap { $0.createdAt }.max() ?? .distantPast) >
            ($1.bits.compactMap { $0.createdAt }.max() ?? .distantPast)
        }
    }

    private var journalStart: Date {
        repository.bits.compactMap { $0.createdAt }.min() ?? Date()
    }
    private var journalEnd: Date {
        repository.bits.compactMap { $0.createdAt }.max() ?? Date()
    }

    var body: some View {
        ScrollView {
            if clusters.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No clusters yet")
                        .foregroundColor(.gray)
                    Text("Add more entries and run the AI pipeline to discover patterns.")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(clusters) { cluster in
                        ClusterCard(
                            cluster: cluster,
                            journalStart: journalStart,
                            journalEnd: journalEnd
                        )
                        .onTapGesture {
                            selectedCluster = cluster
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(item: $selectedCluster) { cluster in
            NavigationView {
                ClusterGraphView(repository: repository, filterClusterID: cluster.index)
            }
        }
    }
}

// MARK: - Cluster Card

private struct ClusterCard: View {
    let cluster: Cluster
    let journalStart: Date
    let journalEnd: Date

    private var activeBits: [Bit] { cluster.bits.filter { !$0.isDeleted } }

    private var dominantEmotion: Emotion? { activeBits.dominantEmotion }

    private var uniqueEmotions: [Emotion] {
        Array(Set(activeBits.map { $0.emotion })).prefix(4).map { $0 }
    }

    private var dateRange: (min: Date, max: Date)? {
        let dates = activeBits.map { $0.createdAt }
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        return (lo, hi)
    }

    private var spanLabel: String {
        guard let range = dateRange else { return "" }
        let days = Calendar.current.dateComponents([.day], from: range.min, to: range.max).day ?? 0
        if days < 2 { return range.min.dayMonth }
        if days < 30 { return "\(days)d span" }
        let months = Int(round(Double(days) / 30.0))
        return "\(months)mo span"
    }

    private var temporalFraction: CGFloat {
        guard let range = dateRange else { return 0 }
        let total = journalEnd.timeIntervalSince(journalStart)
        guard total > 0 else { return 1 }
        let span = range.max.timeIntervalSince(range.min)
        return CGFloat(min(1, span / total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(uniqueEmotions.prefix(4)), id: \.rawValue) { e in
                    Text(e.emoji).font(.title3)
                }
                Spacer()
                Text("\(activeBits.count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }

            Text(cluster.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)

            if !spanLabel.isEmpty {
                Text(spanLabel)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            if let dominant = dominantEmotion {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [dominant.color.opacity(0.7), dominant.color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * temporalFraction), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            (dominantEmotion?.color ?? .gray).opacity(0.25),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

// MARK: - Array uniqued helper

private extension Array where Element: AnyObject {
    func uniqued() -> [Element] {
        var seen = Set<ObjectIdentifier>()
        return filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
