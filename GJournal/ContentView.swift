import SwiftUI
import SwiftData

struct IdentifiableDate: Identifiable {
    let id = UUID()
    let date: Date
}

struct ContentView: View {
    @ObservedObject var repository: BaseJournalRepository
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var selectedDateForSheet: IdentifiableDate?
    @State private var showingAddBit = false
    @State private var showingRepoError = false
    @State private var showingSettings = false
    @State private var showingBitsList = false
    @State private var showingGraph = false

    // New: emotion sheet state
    @State private var selectedEmotion: Emotion? = nil
    @State private var showingEmotionSheet = false

    // Injectable initializer — repository is owned by MainAppView
    init(repository: BaseJournalRepository) {
        self.repository = repository
    }

    @State private var daysWithBits: Set<Date> = []
    @State private var topEmotions: [(emotion: Emotion, count: Int, dates: [Date])] = []

    private func updateDashboardData() {
        self.daysWithBits = repository.getDaysWithBits()
        self.topEmotions = repository.getTopEmotionsLast30Days()
    }

    private var canCreateToday: Bool {
        repository.canCreate(for: Date())
    }

    private var isFirstTimeUser: Bool {
        repository.bits.isEmpty
    }

    /// Get the friendly display name from the user's saved name
    private var displayName: String {
        guard let name = authManager.currentUser, !name.isEmpty else { return "" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                // Dark background
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Greeting header
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(displayName.isEmpty ? greeting : "\(greeting), \(displayName)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text("How are you feeling today?")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    showingBitsList = true
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                        .padding(8)
                                        .background(Color.gray.opacity(0.2))
                                        .clipShape(Circle())
                                }

                                Button {
                                    showingGraph = true
                                } label: {
                                    Image(systemName: "point.3.connected.trianglepath.dotted")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                        .padding(8)
                                        .background(Color.gray.opacity(0.2))
                                        .clipShape(Circle())
                                }

                                Button {
                                    showingSettings = true
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                        .padding(8)
                                        .background(Color.gray.opacity(0.2))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        if isFirstTimeUser {
                            // First-time user welcome
                            FirstTimeWelcomeView {
                                showingAddBit = true
                            }
                        } else {
                            // Regular content for existing users
                            VStack(spacing: 32) {
                                // Calendar section
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
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.gray.opacity(0.1))
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .padding(.horizontal, 20)
                                }

                                // Top emotions section
                                TopEmotionsView(topEmotions: topEmotions) { emotion in
                                    selectedEmotion = emotion
                                    showingEmotionSheet = true
                                }
                            }
                        }

                        Color.clear.frame(height: 100)
                    }
                    .padding(.vertical, 20)
                }

                // Floating Action Button
                if canCreateToday {
                    Button {
                        showingAddBit = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.pink, Color.purple.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 64, height: 64)
                                .shadow(color: Color.pink.opacity(0.4), radius: 12, x: 0, y: 6)

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
            .sheet(item: $selectedDateForSheet) { identifiableDate in
                NavigationView {
                    DayDetailView(repository: repository, date: identifiableDate.date)
                }
            }
            .sheet(isPresented: $showingAddBit) {
                AddEditBitView(repository: repository, bitToEdit: nil, date: Date())
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingBitsList) {
                NavigationView {
                    BitsListView(repository: repository)
                }
            }
            .fullScreenCover(isPresented: $showingGraph) {
                NavigationView {
                    ClusterGraphView(repository: repository)
                }
            }
            // Emotion sheet
            .sheet(isPresented: $showingEmotionSheet) {
                if let emotion = selectedEmotion {
                    NavigationView {
                        EmotionDetailView(repository: repository, emotion: emotion)
                    }
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
        .preferredColorScheme(.dark)
        .onAppear {
            repository.configure(with: modelContext)
            updateDashboardData()
        }
        .onChange(of: repository.bits) {
            updateDashboardData()
        }
    }
}

struct FirstTimeWelcomeView: View {
    let onAddFirstBit: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 32) {
                // Welcome illustration
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.pink.opacity(0.3), Color.purple.opacity(0.2)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.pink)
                }

                VStack(spacing: 20) {
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
                        .lineLimit(nil)
                        .lineSpacing(4)
                }
            }

            Spacer()

            VStack(spacing: 20) {
                Button(action: onAddFirstBit) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)

                        Text("Add Your First Bit")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.pink, Color.purple.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color.pink.opacity(0.4), radius: 12, x: 0, y: 6)
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
