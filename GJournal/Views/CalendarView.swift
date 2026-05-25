//
//  CalendarView.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import SwiftUI

struct CalendarView: View {
    @Binding var month: Date
    let daysWithBits: Set<Date>
    let onDateSelected: (Date) -> Void
    @Binding var selectedDate: Date?
    
    @State private var showingMonthYearPicker = false
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: month)
    }
    
    private var year: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: month)
    }
    
    private var days: [Date?] {
        var days: [Date?] = []
        
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return days
        }
        
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        
        // Add empty days before month starts
        for _ in 1..<firstWeekday {
            days.append(nil)
        }
        
        // Add all days in month
        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Month/Year header with navigation
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }

                Spacer()

                Button {
                    showingMonthYearPicker = true
                } label: {
                    Text("\(monthName) \(year)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            
            // Days of week
            HStack(spacing: 0) {
                ForEach(daysOfWeek.indices, id: \.self) { index in
                    Text(daysOfWeek[index])
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        DayCell(
                            date: date,
                            hasBits: daysWithBits.contains(calendar.startOfDay(for: date)),
                            isSelected: selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!),
                            isToday: calendar.isDateInToday(date)
                        )
                        .onTapGesture {
                            selectedDate = date
                            onDateSelected(date)
                        }
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
        }
        .padding()
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontalSwipe = value.translation.width
                    if horizontalSwipe < -50 {
                        // Swipe left - go to next month
                        changeMonth(by: 1)
                    } else if horizontalSwipe > 50 {
                        // Swipe right - go to previous month
                        changeMonth(by: -1)
                    }
                }
        )
        .sheet(isPresented: $showingMonthYearPicker) {
            MonthYearPickerView(selectedDate: $month)
        }
    }
    
    private func changeMonth(by value: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let newMonth = calendar.date(byAdding: .month, value: value, to: month) {
                month = newMonth
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let hasBits: Bool
    let isSelected: Bool
    let isToday: Bool

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Selected: filled rounded rectangle
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected
                          ? Color(red: 0.42, green: 0.26, blue: 0.88)
                          : Color.clear)
                    .frame(width: 36, height: 36)

                // Today (unselected): subtle outline rectangle
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                }

                Text(dayNumber)
                    .font(.system(size: 15, weight: isToday ? .bold : .regular))
                    .foregroundColor(.white)
            }

            // Entry indicator: small square, not a period-tracker dot
            RoundedRectangle(cornerRadius: 1.5)
                .fill(hasBits
                      ? (isSelected ? Color.white.opacity(0.85) : Color(red: 0.55, green: 0.4, blue: 0.95))
                      : Color.clear)
                .frame(width: 12, height: 3)
        }
        .frame(height: 52)
    }
}

struct MonthYearPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedDate: Date
    
    @State private var tempMonth: Int
    @State private var tempYear: Int
    
    private let calendar = Calendar.current
    private let months = Calendar.current.monthSymbols
    private let currentYear = Calendar.current.component(.year, from: Date())
    private let years: [Int]
    
    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        let components = Calendar.current.dateComponents([.month, .year], from: selectedDate.wrappedValue)
        self._tempMonth = State(initialValue: components.month ?? 1)
        self._tempYear = State(initialValue: components.year ?? Calendar.current.component(.year, from: Date()))
        
        // Create range of years from 2020 to 2030
        self.years = Array(2020...2030)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Month picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Month")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(1...12, id: \.self) { monthIndex in
                            Button {
                                tempMonth = monthIndex
                            } label: {
                                Text(months[monthIndex - 1])
                                    .font(.subheadline)
                                    .fontWeight(tempMonth == monthIndex ? .semibold : .regular)
                                    .foregroundColor(tempMonth == monthIndex ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(tempMonth == monthIndex ? Color.accentColor : Color(uiColor: .systemGray6))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 24)
                
                Divider()
                
                // Year picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Year")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(years, id: \.self) { year in
                                Button {
                                    tempYear = year
                                } label: {
                                    Text("\(year)")
                                        .font(.subheadline)
                                        .fontWeight(tempYear == year ? .semibold : .regular)
                                        .foregroundColor(tempYear == year ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(tempYear == year ? Color.accentColor : Color(uiColor: .systemGray6))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 24)
                
                Spacer()
            }
            .navigationTitle("Select Month & Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        updateSelectedDate()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func updateSelectedDate() {
        var components = DateComponents()
        components.year = tempYear
        components.month = tempMonth
        components.day = 1
        
        if let newDate = calendar.date(from: components) {
            selectedDate = newDate
        }
    }
}
