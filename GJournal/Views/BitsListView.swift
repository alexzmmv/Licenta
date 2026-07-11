import SwiftUI

struct BitsListView: View {
    @ObservedObject var repository: BaseJournalRepository
    @Environment(\.dismiss) var dismiss
    
    var focusSearchOnAppear: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    @State private var searchText = ""
    @State private var selectedEmotions: Set<Emotion> = []
    @State private var showingFilters = false
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var selectedIntensityRange: ClosedRange<Int> = 1...4
    @State private var selectedClusters: Set<Int> = []

    @State private var bitToEdit: Bit?
    @State private var showingDeleteAlert = false
    @State private var bitToDelete: Bit?
    @State private var selectedClusterForGraphID: Int? = nil
    @State private var selectedTab: Tab = .entries

    enum Tab: String, CaseIterable {
        case entries = "Entries"
        case themes = "Themes"
    }

    enum SortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case highIntensity = "Highest Intensity"
        case lowIntensity = "Lowest Intensity"
    }

    @State private var filteredBits: [Bit] = []
    @State private var groupedBits: [(date: Date, bits: [Bit])] = []

    private func updateFilteredData() {
        var results = repository.searchBits(
            query: searchText,
            emotions: selectedEmotions.isEmpty ? nil : Array(selectedEmotions),
            dateRange: nil,
            intensityRange: selectedIntensityRange,
            clusterIDs: selectedClusters.isEmpty ? nil : Array(selectedClusters)
        )

        switch sortOrder {
        case .relevance:
            // Relevance ranking is pre-sorted by the hybridSearch engine
            break
        case .newestFirst:
            results.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            results.sort { $0.createdAt < $1.createdAt }
        case .highIntensity:
            results.sort { $0.intensity > $1.intensity }
        case .lowIntensity:
            results.sort { $0.intensity < $1.intensity }
        }

        self.filteredBits = results

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: results) { bit in
            calendar.startOfDay(for: bit.createdAt)
        }
        self.groupedBits = grouped
            .map { (date: $0.key, bits: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private var activeFilterCount: Int {
        var count = 0
        if !selectedEmotions.isEmpty { count += 1 }
        if selectedIntensityRange != 1...4 { count += 1 }
        if !selectedClusters.isEmpty { count += 1 }
        if sortOrder != .newestFirst { count += 1 }
        return count
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                Picker("View Mode", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                if selectedTab == .entries {
                    entriesView
                } else {
                    themesGridView
                }
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationBarHidden(true)
        .onAppear {
            updateFilteredData()
            if focusSearchOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    isSearchFieldFocused = true
                }
            }
        }
        .onChange(of: repository.bits) { updateFilteredData() }
        .onChange(of: searchText) {
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if sortOrder == .newestFirst {
                    sortOrder = .relevance
                }
            } else {
                if sortOrder == .relevance {
                    sortOrder = .newestFirst
                }
            }
            updateFilteredData()
        }
        .onChange(of: selectedEmotions) { updateFilteredData() }
        .onChange(of: sortOrder) { updateFilteredData() }
        .onChange(of: selectedIntensityRange) { updateFilteredData() }
        .onChange(of: selectedClusters) { updateFilteredData() }
        .sheet(isPresented: $showingFilters) {
            FilterSheetView(
                repository: repository,
                selectedEmotions: $selectedEmotions,
                selectedClusters: $selectedClusters,
                sortOrder: $sortOrder,
                selectedIntensityRange: $selectedIntensityRange,
                searchText: searchText
            )
        }
        .sheet(item: $bitToEdit) { bit in
            AddEditBitView(repository: repository, bitToEdit: bit, date: bit.createdAt)
        }
        .alert("Delete Bit", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                bitToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let bit = bitToDelete {
                    repository.deleteBit(id: bit.id)
                    bitToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this bit? This action cannot be undone.")
        }
        .fullScreenCover(item: Binding(
            get: { selectedClusterForGraphID.map { IdentifiableInt(id: $0) } },
            set: { selectedClusterForGraphID = $0?.id }
        )) { ident in
            NavigationView {
                ClusterGraphView(repository: repository, filterClusterID: ident.id)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }

            Spacer()

            Text("All Entries")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Spacer()

            Button {
                showingFilters = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())

                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Color(red: 0.55, green: 0.4, blue: 0.95))
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search entries...", text: $searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Active Filters

    private var activeFiltersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedEmotions), id: \.self) { emotion in
                    HStack(spacing: 4) {
                        Text(emotion.emoji)
                            .font(.caption)
                        Text(emotion.rawValue)
                            .font(.caption)
                            .foregroundColor(.white)

                        Button {
                            selectedEmotions.remove(emotion)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(emotion.color.opacity(0.25))
                    .cornerRadius(16)
                }
                
                ForEach(Array(selectedClusters).sorted(), id: \.self) { clusterID in
                    HStack(spacing: 4) {
                        Image(systemName: "circle.grid.hex")
                            .font(.caption2)
                            .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                        Text(repository.bits.first(where: { $0.clusterID == clusterID })?.cluster?.displayName ?? "Cluster \(clusterID)")
                            .font(.caption)
                            .foregroundColor(.white)

                        Button {
                            selectedClusters.remove(clusterID)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.15))
                    .cornerRadius(16)
                }

                if selectedClusters.count == 1, let clusterID = selectedClusters.first {
                    Button {
                        selectedClusterForGraphID = clusterID
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.hexagongrid.fill")
                                .font(.caption2)
                            Text("See Theme Graph")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.55, green: 0.4, blue: 0.95))
                        .cornerRadius(16)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }

                if !selectedEmotions.isEmpty || !selectedClusters.isEmpty {
                    Button {
                        selectedEmotions.removeAll()
                        selectedClusters.removeAll()
                    } label: {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: searchText.isEmpty && selectedEmotions.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.6))

            VStack(spacing: 8) {
                Text(searchText.isEmpty && selectedEmotions.isEmpty
                     ? "No entries yet"
                     : "No matching entries")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(searchText.isEmpty && selectedEmotions.isEmpty
                     ? "Start journaling to see your entries here"
                     : "Try adjusting your search or filters")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Bit List

    private var bitListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("\(filteredBits.count) \(filteredBits.count == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: sortOrder == .newestFirst || sortOrder == .highIntensity
                              ? "arrow.down" : "arrow.up")
                            .font(.caption2)
                        Text(sortOrder.rawValue)
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                ForEach(groupedBits, id: \.date) { group in
                    HStack {
                        Text(group.date.sectionHeader)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)

                        Spacer()

                        Text("\(group.bits.count)")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    ForEach(group.bits) { bit in
                        BitCard(
                            bit: bit,
                            canEdit: repository.canEdit(bit: bit),
                            onEdit: {
                                bitToEdit = bit
                            },
                            onDelete: {
                                bitToDelete = bit
                                showingDeleteAlert = true
                            },
                            onToggleHide: {
                                repository.toggleHideBit(id: bit.id)
                            },
                            onClusterTap: { clusterID in
                                selectedClusterForGraphID = clusterID
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }

    @ViewBuilder
    private var entriesView: some View {
        searchBarView

        if !selectedEmotions.isEmpty || !selectedClusters.isEmpty {
            activeFiltersView
        }

        if filteredBits.isEmpty {
            emptyStateView
        } else {
            bitListView
        }
    }

    private var clustersList: [Cluster] {
        let all = repository.bits
            .compactMap { $0.cluster }
            .filter { $0.index >= 0 }
        var seen = Set<ObjectIdentifier>()
        let uniqueClusters = all.filter { seen.insert(ObjectIdentifier($0)).inserted }
        return uniqueClusters.sorted {
            ($0.bits.compactMap { $0.createdAt }.max() ?? .distantPast) >
            ($1.bits.compactMap { $0.createdAt }.max() ?? .distantPast)
        }
    }

    private var themesGridView: some View {
        ScrollView {
            if clustersList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No themes discovered yet")
                        .foregroundColor(.gray)
                    Text("Run the AI pipeline to analyze and group your journal entries.")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(clustersList) { cluster in
                        ClusterCardInList(
                            cluster: cluster,
                            journalStart: repository.bits.compactMap { $0.createdAt }.min() ?? Date(),
                            journalEnd: repository.bits.compactMap { $0.createdAt }.max() ?? Date()
                        )
                        .onTapGesture {
                            selectedClusterForGraphID = cluster.index
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }
}


// MARK: - Filter Sheet

struct FilterSheetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repository: BaseJournalRepository
    @Binding var selectedEmotions: Set<Emotion>
    @Binding var selectedClusters: Set<Int>
    @Binding var sortOrder: BitsListView.SortOrder
    @Binding var selectedIntensityRange: ClosedRange<Int>
    var searchText: String
    
    private var availableClusters: [Int] {
        let ids = Set(repository.bits.compactMap { $0.clusterID }).filter { $0 != -1 }
        return Array(ids).sorted()
    }
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sort By")
                                .font(.headline)
                                .foregroundColor(.white)

                            VStack(spacing: 8) {
                                ForEach(BitsListView.SortOrder.allCases, id: \.self) { order in
                                    if order != .relevance || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Button {
                                            sortOrder = order
                                        } label: {
                                            HStack {
                                                Text(order.rawValue)
                                                    .font(.body)
                                                    .foregroundColor(.white)

                                                Spacer()

                                                if sortOrder == order {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                                                        .fontWeight(.semibold)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(sortOrder == order ? Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.15) : Color.gray.opacity(0.1))
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Filter by Emotion")
                                .font(.headline)
                                .foregroundColor(.white)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Emotion.allCases, id: \.self) { emotion in
                                    Button {
                                        if selectedEmotions.contains(emotion) {
                                            selectedEmotions.remove(emotion)
                                        } else {
                                            selectedEmotions.insert(emotion)
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(selectedEmotions.contains(emotion)
                                                          ? emotion.color
                                                          : Color.gray.opacity(0.2))
                                                    .frame(width: 48, height: 48)

                                                Text(emotion.emoji)
                                                    .font(.title3)
                                            }

                                            Text(emotion.rawValue)
                                                .font(.caption2)
                                                .foregroundColor(selectedEmotions.contains(emotion)
                                                                 ? .white : .gray)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .scaleEffect(selectedEmotions.contains(emotion) ? 1.05 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: selectedEmotions)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Intensity Range")
                                .font(.headline)
                                .foregroundColor(.white)

                            HStack(spacing: 12) {
                                ForEach(1...4, id: \.self) { level in
                                    let isSelected = selectedIntensityRange.contains(level)

                                    Button {
                                        toggleIntensity(level)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Circle()
                                                .fill(isSelected ? Color(red: 0.55, green: 0.4, blue: 0.95) : Color.gray.opacity(0.3))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Text("\(level)")
                                                        .font(.body)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.white)
                                                )

                                            Text(intensityLabel(level))
                                                .font(.caption2)
                                                .foregroundColor(isSelected ? .white : .gray)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !availableClusters.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Filter by Cluster")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(availableClusters, id: \.self) { clusterID in
                                            let isSelected = selectedClusters.contains(clusterID)
                                            Button {
                                                if isSelected {
                                                    selectedClusters.remove(clusterID)
                                                } else {
                                                    selectedClusters.insert(clusterID)
                                                }
                                            } label: {
                                                Text(repository.bits.first(where: { $0.clusterID == clusterID })?.cluster?.displayName ?? "Cluster \(clusterID)")
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 20)
                                                            .fill(isSelected ? Color(red: 0.55, green: 0.4, blue: 0.95) : Color.gray.opacity(0.2))
                                                    )
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Button {
                            selectedEmotions.removeAll()
                            selectedClusters.removeAll()
                            sortOrder = .newestFirst
                            selectedIntensityRange = 1...4
                        } label: {
                            Text("Reset All Filters")
                                .font(.body)
                                .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.15))
                                .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Filters & Sort")
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

    private func toggleIntensity(_ level: Int) {
        if selectedIntensityRange == level...level {
            selectedIntensityRange = 1...4
        } else {
            selectedIntensityRange = level...level
        }
    }

    private func intensityLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Mild"
        case 2: return "Moderate"
        case 3: return "Strong"
        case 4: return "Intense"
        default: return ""
        }
    }
}

struct IdentifiableInt: Identifiable {
    let id: Int
}

struct ClusterCardInList: View {
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
