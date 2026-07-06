import Foundation

enum EmbeddingModelChoice: String, CaseIterable, Identifiable {
    case appleNLP  = "appleNLP"
    case miniLM    = "miniLM"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleNLP:  return "Apple NLP"
        case .miniLM:    return "MiniLM-L6-v2"
        }
    }

    var subtitle: String {
        switch self {
        case .appleNLP:  return "Built-in iOS embedding — fast, zero bundle size"
        case .miniLM:    return "all-MiniLM-L6-v2 — 384-dim, mean pooling, ~45 MB"
        }
    }

    var embeddingDimension: Int {
        switch self {
        case .appleNLP:  return 512
        case .miniLM:    return 384
        }
    }

    private static let defaultsKey = "embeddingModelChoice"

    /// Single source of truth for the active embedding model. Defaults to
    /// MiniLM (best evaluation scores). Stored raw values from removed models
    /// (e.g. the retired Nomic variants) fall back to MiniLM automatically.
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
