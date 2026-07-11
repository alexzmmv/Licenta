import Foundation

struct TextFlattener {
    static func flatten(bit: Bit) -> String {
        var parts: [String] = []

        if let title = bit.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Title] \(title.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if !bit.feel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Feel] \(bit.feel.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if !bit.event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Event] \(bit.event.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if !bit.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Action] \(bit.action.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        return parts.joined(separator: " ")
    }

    static func flatten(title: String?, feel: String, event: String, action: String) -> String {
        var parts: [String] = []

        if let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Title] \(title.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if !feel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Feel] \(feel.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if !event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Event] \(event.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("[Action] \(action.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        return parts.joined(separator: " ")
    }
}
