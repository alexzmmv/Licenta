import SwiftUI

struct TopEmotionsView: View {
    let topEmotions: [(emotion: Emotion, count: Int, dates: [Date])]
    var onEmotionTap: (Emotion) -> Void = { _ in }

    private var maxCount: Int {
        topEmotions.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Emotions")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            if topEmotions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(topEmotions.prefix(5).enumerated()), id: \.element.emotion) { index, item in
                        EmotionBarRow(
                            rank: index + 1,
                            emotion: item.emotion,
                            count: item.count,
                            maxCount: maxCount
                        ) {
                            let impact = UISelectionFeedbackGenerator()
                            impact.selectionChanged()
                            onEmotionTap(item.emotion)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36))
                .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.5))

            VStack(spacing: 6) {
                Text("No patterns yet")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
                Text("Add entries to discover your emotional trends")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassCard()
        .padding(.horizontal, 20)
    }
}

struct EmotionBarRow: View {
    let rank: Int
    let emotion: Emotion
    let count: Int
    let maxCount: Int
    let onTap: () -> Void

    @State private var barProgress: CGFloat = 0

    private var fillFraction: CGFloat {
        maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Emoji
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(emotion.color.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Text(emotion.emoji)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(emotion.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(count) \(count == 1 ? "day" : "days")")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Animated bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 5)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [emotion.color, emotion.color.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * barProgress, height: 5)
                        }
                    }
                    .frame(height: 5)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(Double(rank) * 0.08)) {
                barProgress = fillFraction
            }
        }
    }
}
