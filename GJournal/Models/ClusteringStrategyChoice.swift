//
//  ClusteringStrategyChoice.swift
//  GJournal
//

import Foundation

enum ClusteringStrategyChoice: String, CaseIterable, Identifiable {
    case classic    = "classic"
    case mrlAdapted = "mrlAdapted"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:    return "Classic DBSCAN"
        case .mrlAdapted: return "MRL-Adapted DBSCAN"
        }
    }

    var subtitle: String {
        switch self {
        case .classic:    return "Fixed ε = 0.3 for all embedding dimensions"
        case .mrlAdapted: return "ε scaled by √(dim/768) — tuned for MRL truncations"
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
