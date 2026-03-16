import SwiftUI

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
        repository.getTopEmotionsLastMonth()
    }

    private var canCreateToday: Bool {
        repository.canCreate(for: Date())
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
                ScrollView {
                    VStack(spacing: 24) {
                        // Greeting header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(greeting+", Alex")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }

                            Spacer()
                            
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

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
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                        )
                        .padding(.horizontal)

                        TopEmotionsView(topEmotions: topEmotions) { emotion in
                            selectedEmotion = emotion
                            showingEmotionSheet = true
                        }

                        Color.clear.frame(height: 80)
                    }
                    .padding(.vertical)
                }
                .background(Color(uiColor: .systemGroupedBackground))

                // Floating Action Button
                if canCreateToday {
                    Button {
                        showingAddBit = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.pink.opacity(0.8))
                                .frame(width: 60, height: 60)
                                .shadow(color: Color.pink.opacity(0.4), radius: 12, x: 0, y: 6)

                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
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
        .onAppear {
            // Ensure repository has a ModelContext from SwiftData before performing CRUD
            repository.configure(with: modelContext)
        }
    }
}
