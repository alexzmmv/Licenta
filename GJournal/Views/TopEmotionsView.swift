//
//  TopEmotionsView.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import SwiftUI

struct TopEmotionsView: View {
    let topEmotions: [(emotion: Emotion, count: Int, dates: [Date])]
    var onEmotionTap: (Emotion) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Top Emotions (Last 30 Days)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            if topEmotions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.6))

                    Text("No emotions recorded yet")
                        .font(.body)
                        .foregroundColor(.gray)

                    Text("Add your first bit to see your emotional patterns")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(topEmotions.enumerated()), id: \.element.emotion) { index, item in
                        EmotionRankCard(
                            rank: index + 1,
                            emotion: item.emotion,
                            count: item.count,
                            onTap: {
                                onEmotionTap(item.emotion)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
    }
}

struct EmotionRankCard: View {
    let rank: Int
    let emotion: Emotion
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Text("#\(rank)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                // Emoji with background
                ZStack {
                    Circle()
                        .fill(emotion.color.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Text(emotion.emoji)
                        .font(.title3)
                }

                // Emotion info
                VStack(alignment: .leading, spacing: 4) {
                    Text(emotion.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("\(count) \(count == 1 ? "day" : "days")")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
                    .stroke(emotion.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TopEmotionsView(topEmotions: [(emotion: .joy, count: 5, dates: [Date()])])
}
