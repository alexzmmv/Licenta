//
//  EmbeddingModelChoice.swift
//  GJournal
//
//  Enum representing the user's choice of embedding model.
//  Persisted via UserDefaults so the selection survives app launches.
//

import Foundation

/// The three embedding backends compared in the thesis.
enum EmbeddingModelChoice: String, CaseIterable, Identifiable {
    case appleNLP  = "appleNLP"
    case miniLM    = "miniLM"
    case nomicFull = "nomicFull"
    case nomicMRL  = "nomicMRL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleNLP:  return "Apple NLP"
        case .miniLM:    return "MiniLM-L6-v2"
        case .nomicFull: return "Nomic Full (768d)"
        case .nomicMRL:  return "Nomic MRL (256d)"
        }
    }

    var subtitle: String {
        switch self {
        case .appleNLP:  return "Built-in iOS embedding — fast, zero bundle size"
        case .miniLM:    return "all-MiniLM-L6-v2 — 384-dim, mean pooling, ~45 MB"
        case .nomicFull: return "nomic-embed-text-v1.5 — 768-dim full vector, ~261 MB"
        case .nomicMRL:  return "nomic-embed-text-v1.5 — 256-dim MRL, ~261 MB"
        }
    }

    private static let defaultsKey = "embeddingModelChoice"

    static var current: EmbeddingModelChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let choice = EmbeddingModelChoice(rawValue: raw) else {
                return .miniLM
            }
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .embeddingModelDidChange, object: newValue)
        }
    }
}

extension Notification.Name {
    static let embeddingModelDidChange = Notification.Name("embeddingModelDidChange")
}
