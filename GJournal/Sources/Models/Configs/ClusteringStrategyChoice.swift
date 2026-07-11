import Foundation

enum ClusteringStrategyChoice: String, CaseIterable, Identifiable {
    case classic    = "classic"
    case mrlAdapted = "mrlAdapted"
    case hdbscan    = "hdbscan"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:    return "Classic DBSCAN"
        case .mrlAdapted: return "MRL-Adapted DBSCAN"
        case .hdbscan:    return "HDBSCAN"
        }
    }

    var subtitle: String {
        switch self {
        case .classic:    return "Auto-calibrated ε with silhouette validation"
        case .mrlAdapted: return "Multi-minPts search — tuned for MRL truncations"
        case .hdbscan:    return "Hierarchical density clustering — no ε needed"
        }
    }

    private static let defaultsKey = "clusteringStrategyChoice"

    static var current: ClusteringStrategyChoice {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let choice = ClusteringStrategyChoice(rawValue: raw) else {
                return .classic
            }
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .clusteringStrategyDidChange, object: newValue)
        }
    }
}

extension Notification.Name {
    static let clusteringStrategyDidChange = Notification.Name("clusteringStrategyDidChange")
}
