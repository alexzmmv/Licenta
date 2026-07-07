import SwiftUI
import SwiftData

struct IdentifiableDate: Identifiable {
    let id = UUID()
    let date: Date
}

struct ContentView: View {
    @ObservedObject var repository: BaseJournalRepository
    @EnvironmentObject var authManager: AuthManager
    @Environment(EntitlementManager.self) var entitlementManager
    @Environment(\.modelContext) private var modelContext
    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var selectedDateForSheet: IdentifiableDate?
    @State private var showingAddBit = false
    @State private var showingRepoError = false
    @State private var showingSettings = false
    @State private var showingBitsList = false
    @State private var showingGraph = false
    @State private var showingPaywall = false
    @State private var showingNetworkGraph = false
    @State private var showingTrajectory = false
    @State private var insightEngine = InsightEngine()
    @State private var trajectoryEngine = TrajectoryEngine()
    @State private var bitToEdit: Bit?
    @State private var selectedEmotion: Emotion?
    @State private var showingEmotionSheet = false

    @State private var headerAppeared = false
    @State private var moodCardAppeared = false
    @State private var weekStripAppeared = false
    @State private var calendarAppeared = false
    @State private var recentAppeared = false
    @State private var emotionsAppeared = false
    @State private var insightsAppeared = false

    init(repository: BaseJournalRepository) {
        self.repository = repository
    }

    @State private var daysWithBits: Set<Date> = []
    @State private var topEmotions: [(emotion: Emotion, count: Int, dates: [Date])] = []

    private func updateDashboardData() {
        self.daysWithBits = repository.getDaysWithBits()
        self.topEmotions = repository.getTopEmotionsLast30Days()
    }

    private var canCreateToday: Bool { repository.canCreate(for: Date()) }
    private var isFirstTimeUser: Bool { repository.bits.isEmpty }

    // MARK: - Insight gating
    private var activeBitCount: Int {
        repository.bits.filter { !$0.isDeleted }.count
    }
    private var distinctDayCount: Int {
        Set(repository.bits.filter { !$0.isDeleted }.map {
            Calendar.current.startOfDay(for: $0.createdAt)
        }).count
    }
    // Psychological Network gate: 30 entries AND 14 distinct days
    private var networkProgress: (entries: Int, days: Int) {
        (min(activeBitCount, 30), min(distinctDayCount, 14))
    }
    private var networkUnlocked: Bool { activeBitCount >= 30 && distinctDayCount >= 14 }
    // Trajectory gate: 21 entries AND 21 distinct days
    private var trajectoryProgress: (entries: Int, days: Int) {
        (min(activeBitCount, 21), min(distinctDayCount, 21))
    }
    private var trajectoryUnlocked: Bool { activeBitCount >= 21 && distinctDayCount >= 21 }
    // Smart Search gate: 10 entries
    private var searchUnlocked: Bool { activeBitCount >= 10 }

    private var todayEmotion: Emotion? {
        let calendar = Calendar.current
        let todayBits = repository.bits.filter { !$0.isDeleted && calendar.isDateInToday($0.createdAt) }
        return todayBits.dominantEmotion
    }

    private var weekData: [(date: Date, emotion: Emotion?, intensity: Double)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let dayStart = calendar.startOfDay(for: date)
            let dayBits = repository.bits.filter {
                !$0.isDeleted && calendar.startOfDay(for: $0.createdAt) == dayStart
            }
            let avgIntensity = dayBits.isEmpty ? 0.0 :
                Double(dayBits.map(\.intensity).reduce(0, +)) / Double(dayBits.count)
            return (date: date, emotion: dayBits.dominantEmotion, intensity: avgIntensity)
        }
    }

    private var displayName: String {
        guard let name = authManager.currentUser, !name.isEmpty else { return "" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }

    private var recentEntriesSection: some View {
        let recent = Array(repository.bits
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Entries")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Button { showingBitsList = true } label: {
                    Text("See all")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                }
            }
            .padding(.horizontal, 20)

            if recent.isEmpty {
                Text("No entries yet — tap + to add your first.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { bit in
                        RecentEntryRow(bit: bit) { bitToEdit = bit }
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func animateSections() {
        let spring = Animation.spring(response: 0.55, dampingFraction: 0.78)
        withAnimation(spring) { headerAppeared = true }
        withAnimation(spring.delay(0.1)) { moodCardAppeared = true }
        withAnimation(spring.delay(0.18)) { weekStripAppeared = true }
        withAnimation(spring.delay(0.26)) { calendarAppeared = true }
        withAnimation(spring.delay(0.34)) { recentAppeared = true }
        withAnimation(spring.delay(0.42)) { emotionsAppeared = true }
        withAnimation(spring.delay(0.50)) { insightsAppeared = true }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
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

                ScrollView {
                    VStack(spacing: 28) {
                        headerSection
                            .opacity(headerAppeared ? 1 : 0)
                            .offset(y: headerAppeared ? 0 : -12)

                        if isFirstTimeUser {
                            FirstTimeWelcomeView { showingAddBit = true }
                        } else {
                            TodayMoodCard(emotion: todayEmotion)
                                .padding(.horizontal, 20)
                                .opacity(moodCardAppeared ? 1 : 0)
                                .offset(y: moodCardAppeared ? 0 : 20)

                            WeekMoodStrip(weekData: weekData) { date in
                                selectedDate = date
                                selectedDateForSheet = IdentifiableDate(date: date)
                            }
                            .opacity(weekStripAppeared ? 1 : 0)
                            .offset(y: weekStripAppeared ? 0 : 20)

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Your Journey")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)

                                CalendarView(
                                    month: $currentMonth,
                                    daysWithBits: daysWithBits,
                                    onDateSelected: { date in
                                        selectedDate = date
                                        selectedDateForSheet = IdentifiableDate(date: date)
                                    },
                                    selectedDate: $selectedDate
                                )
                                .glassCard()
                                .padding(.horizontal, 20)
                            }
                            .opacity(calendarAppeared ? 1 : 0)
                            .offset(y: calendarAppeared ? 0 : 20)

                            recentEntriesSection
                                .opacity(recentAppeared ? 1 : 0)
                                .offset(y: recentAppeared ? 0 : 20)

                            TopEmotionsView(topEmotions: topEmotions) { emotion in
                                selectedEmotion = emotion
                                showingEmotionSheet = true
                            }
                            .opacity(emotionsAppeared ? 1 : 0)
                            .offset(y: emotionsAppeared ? 0 : 20)

                            InsightGatingSection(
                                networkProgress: networkProgress,
                                networkUnlocked: networkUnlocked,
                                trajectoryProgress: trajectoryProgress,
                                trajectoryUnlocked: trajectoryUnlocked,
                                searchUnlocked: searchUnlocked,
                                totalEntries: activeBitCount,
                                isPurchased: entitlementManager.hasInsights,
                                onUnlock: { showingPaywall = true },
                                onOpenSearch: { showingBitsList = true },
                                onOpenNetwork: { showingNetworkGraph = true },
                                onOpenTrajectory: { showingTrajectory = true }
                            )
                            .opacity(insightsAppeared ? 1 : 0)
                            .offset(y: insightsAppeared ? 0 : 20)
                        }

                        Color.clear.frame(height: 100)
                    }
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                if canCreateToday {
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        showingAddBit = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.3, blue: 0.95), Color(red: 0.42, green: 0.26, blue: 0.88)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 64, height: 64)
                                .shadow(color: Color(red: 0.6, green: 0.2, blue: 0.9).opacity(0.5), radius: 16, x: 0, y: 8)

                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedDateForSheet) { id in
                NavigationStack { DayDetailView(repository: repository, date: id.date) }
            }
            .sheet(isPresented: $showingAddBit) {
                AddEditBitView(repository: repository, bitToEdit: nil, date: Date())
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(repository: repository)
            }
            .sheet(item: $bitToEdit) { bit in
                AddEditBitView(repository: repository, bitToEdit: bit, date: bit.createdAt)
            }
            .fullScreenCover(isPresented: $showingBitsList) {
                NavigationStack { BitsListView(repository: repository) }
            }
            .fullScreenCover(isPresented: $showingGraph) {
                NavigationStack { ClusterGraphView(repository: repository) }
            }
            .sheet(isPresented: $showingEmotionSheet) {
                if let emotion = selectedEmotion {
                    NavigationStack { EmotionDetailView(repository: repository, emotion: emotion) }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environment(entitlementManager)
            }
            .sheet(isPresented: $showingNetworkGraph) {
                if let net = insightEngine.network {
                    NetworkGraphView(network: net)
                } else {
                    NetworkGraphLoadingView()
                }
            }
            .onChange(of: showingNetworkGraph) { _, isShowing in
                guard isShowing else { return }
                Task { await insightEngine.compute(bits: repository.bits) }
            }
            .sheet(isPresented: $showingTrajectory) {
                TrajectoryView(metrics: trajectoryEngine.metrics)
            }
            .onChange(of: showingTrajectory) { _, isShowing in
                guard isShowing else { return }
                trajectoryEngine.metrics = nil
                Task { await trajectoryEngine.compute(bits: repository.bits) }
            }
            .onReceive(repository.$errorMessage) { new in
                showingRepoError = new != nil
            }
            .alert("Error", isPresented: $showingRepoError) {
                Button("OK") { repository.errorMessage = nil }
            } message: {
                Text(repository.errorMessage ?? "Unknown error")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            repository.configure(with: modelContext)
            updateDashboardData()
            animateSections()
        }
        .onChange(of: repository.bits) { updateDashboardData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.isEmpty ? greeting : "\(greeting),")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                if !displayName.isEmpty {
                    Text(displayName)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                headerButton(icon: "list.bullet") { showingBitsList = true }
                headerButton(icon: "point.3.connected.trianglepath.dotted") { showingGraph = true }
                headerButton(icon: "gearshape.fill") { showingSettings = true }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}

// MARK: - Glass Card Modifier

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Today Mood Card

struct TodayMoodCard: View {
    let emotion: Emotion?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().weekdayName.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.5)
                Text(Date().monthDay)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(emotion != nil ? "You're feeling \(emotion!.rawValue.lowercased()) today" : "How are you feeling today?")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }
            Spacer()
            Text(emotion?.emoji ?? "✨")
                .font(.system(size: 60))
                .shadow(color: (emotion?.color ?? Color(red: 0.6, green: 0.3, blue: 0.9)).opacity(0.6), radius: 12)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        (emotion?.color ?? Color(red: 0.42, green: 0.26, blue: 0.88)).opacity(0.45),
                        (emotion?.color ?? Color(red: 0.42, green: 0.26, blue: 0.88)).opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Week Mood Strip

struct WeekMoodStrip: View {
    let weekData: [(date: Date, emotion: Emotion?, intensity: Double)]
    let onDateTapped: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            HStack(spacing: 6) {
                ForEach(weekData.indices, id: \.self) { i in
                    let day = weekData[i]
                    WeekDayPill(
                        date: day.date,
                        emotion: day.emotion,
                        isToday: Calendar.current.isDateInToday(day.date)
                    )
                    .onTapGesture {
                        if day.emotion != nil {
                            let impact = UISelectionFeedbackGenerator()
                            impact.selectionChanged()
                            onDateTapped(day.date)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct WeekDayPill: View {
    let date: Date
    let emotion: Emotion?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(date.weekdayLetter)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(emotion != nil
                          ? emotion!.color.opacity(0.25)
                          : Color.white.opacity(0.04))
                    .frame(width: 38, height: 46)

                if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 38, height: 46)
                }

                if let emotion = emotion {
                    Text(emotion.emoji)
                        .font(.system(size: 22))
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.4))
                }
            }

            Text(date.dayNumber)
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : .gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recent Entry Row

struct RecentEntryRow: View {
    let bit: Bit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Emotion badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(bit.emotion.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text(bit.emotion.emoji)
                        .font(.title3)
                }

                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    Text(bit.title ?? String(bit.feel.prefix(40)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(bit.feel.isEmpty ? bit.event : bit.feel)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Spacer()

                // Date + intensity
                VStack(alignment: .trailing, spacing: 5) {
                    Text(bit.createdAt.shortRelative)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    HStack(spacing: 3) {
                        ForEach(1...4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i <= bit.intensity
                                      ? bit.emotion.color.opacity(0.8)
                                      : Color.white.opacity(0.08))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .glassCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - First-Time Welcome

struct FirstTimeWelcomeView: View {
    let onAddFirstBit: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.8, green: 0.3, blue: 0.95).opacity(0.3),
                                         Color(red: 0.42, green: 0.26, blue: 0.88).opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Text("✨")
                        .font(.system(size: 60))
                }

                VStack(spacing: 16) {
                    Text("Welcome to Your Journey")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Start your emotional wellness journey by creating your first story. Share how you're feeling, what happened, and what you plan to do about it.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .lineSpacing(4)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: onAddFirstBit) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                        Text("Add Your First Bit").font(.headline).fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.8, green: 0.3, blue: 0.95), Color(red: 0.42, green: 0.26, blue: 0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color(red: 0.6, green: 0.2, blue: 0.9).opacity(0.4), radius: 14, x: 0, y: 6)
                }
                .padding(.horizontal, 32)

                Text("Let's begin your story...")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .italic()
            }
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Insight Gating Section

/// Shows locked/purchasable/unlocked cards for the three paid insight pillars.
struct InsightGatingSection: View {
    let networkProgress: (entries: Int, days: Int)
    let networkUnlocked: Bool
    let trajectoryProgress: (entries: Int, days: Int)
    let trajectoryUnlocked: Bool
    let searchUnlocked: Bool
    let totalEntries: Int
    let isPurchased: Bool
    let onUnlock: () -> Void
    let onOpenSearch: () -> Void
    let onOpenNetwork: (() -> Void)?
    let onOpenTrajectory: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Insights")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    InsightGateCard(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "Psychological Network",
                        description: "See how your emotions and behaviours connect across time.",
                        accentColor: Color(red: 0.55, green: 0.4, blue: 0.95),
                        isUnlocked: networkUnlocked,
                        isPurchased: isPurchased,
                        progressLabel: "\(networkProgress.entries)/30 entries \u{00B7} \(networkProgress.days)/14 days",
                        onUnlock: onUnlock,
                        onOpen: onOpenNetwork
                    )

                    InsightGateCard(
                        icon: "waveform.path",
                        title: "Trajectory Analysis",
                        description: "Track emotional loops, exploration and semantic recovery over time.",
                        accentColor: Color(red: 0.2, green: 0.7, blue: 0.9),
                        isUnlocked: trajectoryUnlocked,
                        isPurchased: isPurchased,
                        progressLabel: "\(trajectoryProgress.entries)/21 entries \u{00B7} \(trajectoryProgress.days)/21 days",
                        onUnlock: onUnlock,
                        onOpen: onOpenTrajectory
                    )

                    InsightGateCard(
                        icon: "magnifyingglass.circle",
                        title: "Smart Search",
                        description: "Find entries by meaning, not just keywords — hybrid AI search.",
                        accentColor: Color(red: 0.9, green: 0.55, blue: 0.25),
                        isUnlocked: searchUnlocked,
                        isPurchased: isPurchased,
                        progressLabel: "\(min(totalEntries, 10))/10 entries",
                        onUnlock: onUnlock,
                        onOpen: onOpenSearch
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
    }
}

struct InsightGateCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let isUnlocked: Bool
    let isPurchased: Bool
    let progressLabel: String
    let onUnlock: (() -> Void)?
    let onOpen: (() -> Void)?

    @State private var ringProgress: CGFloat = 0

    private var fraction: CGFloat {
        let parts = progressLabel.split(separator: "\u{00B7}").first ?? Substring(progressLabel)
        let nums = parts.split(separator: "/").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count == 2, nums[1] > 0 else { return isUnlocked ? 1 : 0 }
        return CGFloat(min(nums[0], nums[1])) / CGFloat(nums[1])
    }

    private var badgeLabel: String {
        if !isUnlocked { return "Soon" }
        if isPurchased { return onOpen != nil ? "Open" : "Ready" }
        return "Unlock"
    }

    private var badgeColor: Color {
        if !isUnlocked { return .gray }
        if isPurchased { return accentColor }
        return Color(red: 0.9, green: 0.7, blue: 0.2)
    }

    var body: some View {
        Button(action: {
            if isUnlocked && isPurchased { onOpen?() }
            else if isUnlocked { onUnlock?() }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .stroke(accentColor.opacity(0.15), lineWidth: 3)
                            .frame(width: 46, height: 46)
                        Circle()
                            .trim(from: 0, to: ringProgress)
                            .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 46, height: 46)
                        Image(systemName: isUnlocked ? icon : "lock.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isUnlocked ? accentColor : .gray)
                    }

                    Spacer()

                    Text(badgeLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badgeColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isUnlocked ? .white : .white.opacity(0.6))
                        .lineLimit(1)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !isUnlocked {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundColor(accentColor.opacity(0.8))
                        .lineLimit(1)
                } else if !isPurchased {
                    Text("Tap to unlock all three pillars")
                        .font(.caption2)
                        .foregroundColor(badgeColor.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accentColor.opacity(isUnlocked ? 0.35 : 0.12), lineWidth: 1)
                    )
            )
            .shadow(color: isUnlocked ? accentColor.opacity(0.15) : .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.2)) {
                ringProgress = isUnlocked ? 1 : fraction
            }
        }
        .onChange(of: isUnlocked) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                ringProgress = isUnlocked ? 1 : fraction
            }
        }
    }
}
