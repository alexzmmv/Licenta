import Foundation
import SwiftUI

enum Emotion: String, CaseIterable, Codable {
    case joy = "Joy"
    case sadness = "Sadness"
    case anger = "Anger"
    case fear = "Fear"
    case love = "Love"
    case surprise = "Surprise"
    case disgust = "Disgust"
    case anxiety = "Anxiety"
    case excitement = "Excitement"
    case gratitude = "Gratitude"
    case hope = "Hope"
    case guilt = "Guilt"
    
    var emoji: String {
        switch self {
        case .joy: return "😊"
        case .sadness: return "😢"
        case .anger: return "😠"
        case .fear: return "😰"
        case .love: return "❤️"
        case .surprise: return "😲"
        case .disgust: return "🤢"
        case .anxiety: return "😟"
        case .excitement: return "🤩"
        case .gratitude: return "🙏"
        case .hope: return "🌟"
        case .guilt: return "😔"
        }
    }
    
    var color: Color {
        switch self {
        case .joy: return Color(red: 1.0, green: 0.8, blue: 0.0) // Bright yellow
        case .sadness: return Color(red: 0.3, green: 0.5, blue: 0.9) // Light blue
        case .anger: return Color(red: 0.95, green: 0.3, blue: 0.3) // Bright red
        case .fear: return Color(red: 0.7, green: 0.4, blue: 0.9) // Bright purple
        case .love: return Color(red: 1.0, green: 0.4, blue: 0.6) // Bright pink
        case .surprise: return Color(red: 1.0, green: 0.6, blue: 0.2) // Bright orange
        case .disgust: return Color(red: 0.4, green: 0.8, blue: 0.4) // Bright green
        case .anxiety: return Color(red: 0.6, green: 0.6, blue: 0.65) // Light gray
        case .excitement: return Color(red: 0.5, green: 0.9, blue: 0.9) // Bright mint
        case .gratitude: return Color(red: 0.3, green: 0.8, blue: 0.7) // Bright teal
        case .hope: return Color(red: 0.4, green: 0.85, blue: 1.0) // Bright cyan
        case .guilt: return Color(red: 0.7, green: 0.5, blue: 0.35) // Light brown
        }
    }
}
