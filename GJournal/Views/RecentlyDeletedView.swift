//
//  RecentlyDeletedView.swift
//  GJournal
//
//  Displays soft-deleted micro-journal bits.
//  Enables users to restore entries or permanently purge them before
//  automatic 72-hour system retention sweeps.
//

import SwiftUI

struct RecentlyDeletedView: View {
    @ObservedObject var repository: BaseJournalRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background: black + subtle purple glow at bottom
            ZStack(alignment: .bottom) {
                Color.black
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.18, green: 0.08, blue: 0.38).opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
            }
            .ignoresSafeArea()

            VStack(spacing: 1) {
                // Header
                HStack {
                    Text("Recently Deleted")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        
                        
                    Spacer()
                    
                    // Invisible spacer to balance back button
                    HStack {
                        Image(systemName: "chevron.left").opacity(0)
                        Text("Back").opacity(0)
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)

                if repository.deletedBits.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Advisory banner
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.8, green: 0.4, blue: 0.9))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Temporary Storage")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Deleted entries will be kept here for exactly 72 hours before being permanently purged. Restoring an entry re-integrates it back into your wellness graph.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineSpacing(3)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .glassCard()
                            .padding(.horizontal, 20)
                            
                            VStack(spacing: 10) {
                                ForEach(repository.deletedBits) { bit in
                                    DeletedEntryRow(bit: bit, repository: repository)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(red: 0.18, green: 0.08, blue: 0.38).opacity(0.3))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.8))
            }

            VStack(spacing: 8) {
                Text("Trash is Empty")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Deleted entries will appear here for 3 days before they are permanently deleted from your device.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .lineSpacing(3)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeletedEntryRow: View {
    let bit: Bit
    let repository: BaseJournalRepository
    
    @State private var showingConfirmDelete = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // Emotion badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(bit.emotion.color.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Text(bit.emotion.emoji)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(bit.title ?? String((bit.feel.isEmpty ? bit.event : bit.feel).prefix(32)))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let hours = bit.retentionHoursRemaining {
                        Text("\(hours)h remaining before purge")
                            .font(.caption2)
                            .foregroundColor(hours < 12 ? .red.opacity(0.8) : Color(red: 0.8, green: 0.4, blue: 0.95))
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
            }
            
            // Micro-journal snippet preview
            VStack(alignment: .leading, spacing: 4) {
                if !bit.feel.isEmpty {
                    Text("Feel: \(bit.feel)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                if !bit.event.isEmpty {
                    Text("Event: \(bit.event)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 2)
            
            HStack(spacing: 12) {
                // Restore button
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    repository.restoreBit(id: bit.id)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("Restore")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                
                // Delete permanently button
                Button {
                    showingConfirmDelete = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.caption)
                        Text("Delete")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.18), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 18)
        .alert("Permanently Delete?", isPresented: $showingConfirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let impact = UINotificationFeedbackGenerator()
                impact.notificationOccurred(.warning)
                repository.permanentlyDeleteBit(id: bit.id)
            }
        } message: {
            Text("This action is completely destructive and cannot be undone. All database records and spatial graph nodes for this entry will be lost.")
        }
    }
}
