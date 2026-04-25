//
//  TextFlattener.swift
//  GJournal
//
//  Combines journal entry fields into a single text string
//  suitable for embedding with a BERT-family Core ML model.
//

import Foundation

/// Combines Bit fields into a single text string for BERT model input.
///
/// The flattened format uses tagged sections so the model can distinguish
/// between the feel, event, and action components:
///
///     [Title] My story [Feel] I felt happy [Event] Had a great meeting [Action] Will celebrate
///
struct TextFlattener {
    /// Flatten a Bit's text fields into a single string for model input.
    /// - Parameter bit: The journal entry to flatten.
    /// - Returns: A combined text string with section tags.
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

    /// Flatten raw text fields (before a Bit is created).
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
