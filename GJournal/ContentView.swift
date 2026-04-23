import SwiftUI
import SwiftData

struct IdentifiableDate: Identifiable {
    let id = UUID()
    let date: Date
}

struct ContentView: View {
    @StateObject private var repository: BaseJournalRepository
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var selectedDateForSheet: IdentifiableDate?
    @State private var showingAddBit = false
    @State private var showingRepoError = false
    @State private var showingSettings = false

    // New: emotion sheet state
    @State private var selectedEmotion: Emotion? = nil
    @State private var showingEmotionSheet = false

    // Injectable initializer
    init(repository: BaseJournalRepository) {
        _repository = StateObject(wrappedValue: repository)
    }

    private var daysWithBits: Set<Date> {
        repository.getDaysWithBits()
    }

    private var topEmotions: [(emotion: Emotion, count: Int, dates: [Date])] {
        repository.getTopEmotionsLast30Days()
    }

    private var canCreateToday: Bool {
        repository.canCreate(for: Date())
    }

    private var isFirstTimeUser: Bool {
        repository.bits.isEmpty
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
                                Text(greeting+", Alex")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text("How are you feeling today?")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

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
            // Ensure repository has a ModelContext from SwiftData before performing CRUD
            repository.configure(with: modelContext)
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
