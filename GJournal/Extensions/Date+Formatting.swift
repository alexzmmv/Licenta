import Foundation

private var formatterCache: [String: DateFormatter] = [:]
private func formatter(format: String) -> DateFormatter {
    if let cached = formatterCache[format] { return cached }
    let f = DateFormatter()
    f.dateFormat = format
    formatterCache[format] = f
    return f
}

extension Date {
    /// "h:mm a" — used in entry cards
    var timeOfDay: String { formatter(format: "h:mm a").string(from: self) }

    /// "MMM d" — used in graph node labels and recent-entry rows
    var dayMonth: String { formatter(format: "MMM d").string(from: self) }

    /// "MMM d, yyyy" — used in detail views
    var dayMonthYear: String { formatter(format: "MMM d, yyyy").string(from: self) }

    /// "MMM yyyy" — used in cluster span labels
    var monthYear: String { formatter(format: "MMM yyyy").string(from: self) }

    /// "EEEE" — full weekday name
    var weekdayName: String { formatter(format: "EEEE").string(from: self) }

    /// "EEEEE" — single-letter weekday (Mon Strip pills)
    var weekdayLetter: String { formatter(format: "EEEEE").string(from: self) }

    /// "d" — day number only
    var dayNumber: String { formatter(format: "d").string(from: self) }

    /// "MMMM d" — month + day (Today mood card date string)
    var monthDay: String { formatter(format: "MMMM d").string(from: self) }

    /// Section header: "Today", "Yesterday", weekday name, or "MMMM d" / "MMMM d, yyyy"
    var sectionHeader: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) {
            return weekdayName
        }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return monthDay
        }
        return formatter(format: "MMMM d, yyyy").string(from: self)
    }

    /// Short label: "Today", "Yesterday", or "MMM d"
    var shortRelative: String {
        let c = Calendar.current
        if c.isDateInToday(self) { return "Today" }
        if c.isDateInYesterday(self) { return "Yesterday" }
        return dayMonth
    }
}
