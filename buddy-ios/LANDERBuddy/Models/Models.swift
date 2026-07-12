import Foundation

// MARK: - Team

struct Team: Codable, Identifiable {
    let id: UUID
    var name: String
    var thresholds: Thresholds
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, thresholds
        case createdAt = "created_at"
    }
}

// MARK: - Thresholds (tunable in Settings)

struct Thresholds: Codable {
    var valgusYellowDeg: Double
    var valgusRedDeg: Double
    var flexionYellowDeg: Double
    var flexionRedDeg: Double
    var deltaYellowPct: Double
    var deltaRedPct: Double
    var baselineNSessions: Int
    
    enum CodingKeys: String, CodingKey {
        case valgusYellowDeg = "valgus_yellow_deg"
        case valgusRedDeg = "valgus_red_deg"
        case flexionYellowDeg = "flexion_yellow_deg"
        case flexionRedDeg = "flexion_red_deg"
        case deltaYellowPct = "delta_yellow_pct"
        case deltaRedPct = "delta_red_pct"
        case baselineNSessions = "baseline_n_sessions"
    }
    
    static let defaults = Thresholds(
        valgusYellowDeg: 5,
        valgusRedDeg: 10,
        flexionYellowDeg: 45,
        flexionRedDeg: 30,
        deltaYellowPct: 10,
        deltaRedPct: 20,
        baselineNSessions: 3
    )
}

// MARK: - Profile

struct Profile: Codable, Identifiable {
    let id: UUID
    var teamId: UUID?
    var role: UserRole
    var fullName: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, role
        case teamId = "team_id"
        case fullName = "full_name"
        case createdAt = "created_at"
    }
}

enum UserRole: String, Codable {
    case trainer
    case coach
}

// MARK: - Athlete

struct Athlete: Codable, Identifiable, Hashable {
    let id: UUID
    let teamId: UUID
    var name: String
    var jerseyNumber: String
    var position: String
    var active: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, position, active
        case teamId = "team_id"
        case jerseyNumber = "jersey_number"
        case createdAt = "created_at"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Athlete, rhs: Athlete) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session

enum SessionState: String, Codable, CaseIterable {
    case fresh
    case fatigued
    
    var label: String {
        switch self {
        case .fresh: return "Fresh (warm-up)"
        case .fatigued: return "Fatigued (end of practice)"
        }
    }
    
    var shortLabel: String {
        rawValue.capitalized
    }
}

struct CaptureSession: Codable, Identifiable {
    let id: UUID
    let teamId: UUID
    var date: Date
    var state: SessionState
    var notes: String?
    var createdBy: UUID?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, date, state, notes
        case teamId = "team_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

// MARK: - Capture (one per athlete-jump)

struct Capture: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let athleteId: UUID
    var kneeValgusDeg: Double?
    var kneeFlexionDeg: Double?
    var trunkLeanDeg: Double?
    var lessScore: Double?
    var riskLevel: String?
    var asymmetryIndex: Double?
    var vulnerabilityScore: Double?
    var fatigueCategory: String?
    var modelVersion: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case athleteId = "athlete_id"
        case kneeValgusDeg = "knee_valgus_deg"
        case kneeFlexionDeg = "knee_flexion_deg"
        case trunkLeanDeg = "trunk_lean_deg"
        case lessScore = "less_score"
        case riskLevel = "risk_level"
        case asymmetryIndex = "asymmetry_index"
        case vulnerabilityScore = "vulnerability_score"
        case fatigueCategory = "fatigue_category"
        case modelVersion = "model_version"
        case createdAt = "created_at"
    }
}

// MARK: - Readiness (computed, not stored)

enum ReadinessStatus: String, CaseIterable {
    case green, yellow, red, none
    
    var label: String {
        switch self {
        case .green: return "Good"
        case .yellow: return "Caution"
        case .red: return "High Risk"
        case .none: return "No Data"
        }
    }
}

enum TrendDirection: String {
    case improving, stable, worsening, unknown
    
    var label: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .improving: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .worsening: return "arrow.up.right"
        case .unknown: return "minus"
        }
    }
    
    var symbol: String {
        switch self {
        case .improving: return "↓"
        case .stable: return "→"
        case .worsening: return "↑"
        case .unknown: return "—"
        }
    }
}

struct AthleteReadiness: Identifiable {
    var id: UUID { athlete.id }
    let athlete: Athlete
    var status: ReadinessStatus
    var trend: TrendDirection
    var latestValgus: Double?
    var latestFlexion: Double?
    var fatigueDeltaPct: Double?
    var vulnerabilityScore: Double?
    var note: String
    var hasBaseline: Bool
    var weeksOfData: Int
    var recommendation: String
}

// MARK: - CV Model Response

struct ModelMetrics {
    var kneeValgusDeg: Double
    var kneeFlexionDeg: Double
    var trunkLeanDeg: Double
    var lessScore: Double
    var riskLevel: String
    var asymmetryIndex: Double
}

// MARK: - Capture Item (used in the capture flow UI)

struct CaptureItem: Identifiable {
    let id = UUID()
    var videoURL: URL?
    var athleteId: UUID?
    var athleteName: String = ""
    var status: CaptureItemStatus = .pending
    var metrics: ModelMetrics?
    var error: String?
}

enum CaptureItemStatus {
    case pending, processing, done, error
}
