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
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Emotions (Last 30 Days)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            if topEmotions.isEmpty {
                Text("No emotions recorded yet")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(topEmotions.enumerated()), id: \.element.emotion) { index, item in
                        EmotionRankCard(
                            rank: index + 1,
                            emotion: item.emotion,
                            count: item.count
                        )
                        .onTapGesture {
                            onEmotionTap(item.emotion)
                        }
                    }
                }
            }
        }
        .padding(.vertical)
    }
}

struct EmotionRankCard: View {
    let rank: Int
    let emotion: Emotion
    let count: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 50, height: 50)
                
                Text("#\(rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            // Emoji
            ZStack {
                Circle()
                    .fill(emotion.color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Text(emotion.emoji)
                    .font(.title2)
            }
            
            // Emotion info
            VStack(alignment: .leading, spacing: 4) {
                Text(emotion.rawValue)
                    .font(.headline)
                
                Text("\(count) bits")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
}

#Preview {
    TopEmotionsView(topEmotions: [(emotion: .joy, count: 5, dates: [Date()])])
}
