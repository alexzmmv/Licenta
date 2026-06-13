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
    var timeOfDay: String { formatter(format: "h:mm a").string(from: self) }

    var dayMonth: String { formatter(format: "MMM d").string(from: self) }

    var dayMonthYear: String { formatter(format: "MMM d, yyyy").string(from: self) }

    var monthYear: String { formatter(format: "MMM yyyy").string(from: self) }

    var weekdayName: String { formatter(format: "EEEE").string(from: self) }

    var weekdayLetter: String { formatter(format: "EEEEE").string(from: self) }

    var dayNumber: String { formatter(format: "d").string(from: self) }

    var monthDay: String { formatter(format: "MMMM d").string(from: self) }

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

    var shortRelative: String {
        let c = Calendar.current
        if c.isDateInToday(self) { return "Today" }
        if c.isDateInYesterday(self) { return "Yesterday" }
        return dayMonth
    }
}
