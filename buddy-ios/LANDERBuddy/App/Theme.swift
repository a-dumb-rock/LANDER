import SwiftUI

// MARK: - Brand Colors

extension Color {
    static let brand = Color(red: 14/255, green: 165/255, blue: 233/255)         // #0EA5E9
    static let brandDark = Color(red: 2/255, green: 132/255, blue: 199/255)      // #0284C7
    static let brandLight = Color(red: 56/255, green: 189/255, blue: 248/255)    // #38BDF8
    
    // Status colors
    static let statusGreen = Color(red: 34/255, green: 197/255, blue: 94/255)
    static let statusYellow = Color(red: 234/255, green: 179/255, blue: 8/255)
    static let statusRed = Color(red: 239/255, green: 68/255, blue: 68/255)
    
    static let statusGreenBg = Color(red: 220/255, green: 252/255, blue: 231/255)
    static let statusYellowBg = Color(red: 254/255, green: 249/255, blue: 195/255)
    static let statusRedBg = Color(red: 254/255, green: 226/255, blue: 226/255)
    
    static let statusGreenText = Color(red: 21/255, green: 128/255, blue: 61/255)
    static let statusYellowText = Color(red: 133/255, green: 77/255, blue: 14/255)
    static let statusRedText = Color(red: 185/255, green: 28/255, blue: 28/255)
}

// MARK: - Status Helpers

extension ReadinessStatus {
    var color: Color {
        switch self {
        case .green: return .statusGreen
        case .yellow: return .statusYellow
        case .red: return .statusRed
        case .none: return .gray
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .green: return .statusGreenBg
        case .yellow: return .statusYellowBg
        case .red: return .statusRedBg
        case .none: return Color(.systemGray5)
        }
    }
    
    var textColor: Color {
        switch self {
        case .green: return .statusGreenText
        case .yellow: return .statusYellowText
        case .red: return .statusRedText
        case .none: return .secondary
        }
    }
}

extension TrendDirection {
    var color: Color {
        switch self {
        case .improving: return .statusGreen
        case .stable: return .secondary
        case .worsening: return .statusRed
        case .unknown: return .secondary
        }
    }
}
