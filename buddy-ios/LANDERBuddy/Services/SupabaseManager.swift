import Foundation
import Supabase

// MARK: - Codable DTOs for Supabase inserts/updates

struct TeamInsert: Codable {
    let name: String
}

struct TeamUpdate: Codable {
    var name: String?
    var thresholds: Thresholds?
}

struct ProfileUpdate: Codable {
    var team_id: String?
    var role: String?
}

struct AthleteInsert: Codable {
    let team_id: String
    let name: String
    let jersey_number: String
    let position: String
}

struct AthleteUpdate: Codable {
    var name: String?
    var jersey_number: String?
    var position: String?
    var active: Bool?
}

struct SessionInsert: Codable {
    let team_id: String
    let date: String
    let state: String
    let created_by: String
}

struct CaptureInsert: Codable {
    let session_id: String
    let athlete_id: String
    let knee_valgus_deg: Double
    let knee_flexion_deg: Double
    let trunk_lean_deg: Double
    let less_score: Double
    let risk_level: String
    let asymmetry_index: Double
    let model_version: String
}

// MARK: - Supabase Manager

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        let url = URL(string: Config.supabaseURL)!
        let key = Config.supabaseAnonKey
        
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key
        )
    }
    
    // MARK: - Team
    
    func getTeam() async throws -> Team? {
        let profile: Profile = try await client.from("profiles")
            .select()
            .eq("id", value: client.auth.session.user.id)
            .single()
            .execute()
            .value
        
        guard let teamId = profile.teamId else { return nil }
        
        let team: Team = try await client.from("teams")
            .select()
            .eq("id", value: teamId)
            .single()
            .execute()
            .value
        
        return team
    }
    
    func createTeam(name: String) async throws -> Team {
        let team: Team = try await client.from("teams")
            .insert(TeamInsert(name: name))
            .select()
            .single()
            .execute()
            .value
        
        return team
    }
    
    func updateTeam(id: UUID, name: String, thresholds: Thresholds) async throws {
        try await client.from("teams")
            .update(TeamUpdate(name: name, thresholds: thresholds))
            .eq("id", value: id)
            .execute()
    }
    
    // MARK: - Profile
    
    func updateProfile(userId: UUID, teamId: UUID, role: UserRole) async throws {
        try await client.from("profiles")
            .update(ProfileUpdate(team_id: teamId.uuidString, role: role.rawValue))
            .eq("id", value: userId)
            .execute()
    }
    
    // MARK: - Athletes
    
    func getAthletes(teamId: UUID) async throws -> [Athlete] {
        let athletes: [Athlete] = try await client.from("athletes")
            .select()
            .eq("team_id", value: teamId)
            .eq("active", value: true)
            .order("jersey_number")
            .execute()
            .value
        
        return athletes
    }
    
    func addAthlete(teamId: UUID, name: String, jerseyNumber: String, position: String) async throws -> Athlete {
        let athlete: Athlete = try await client.from("athletes")
            .insert(AthleteInsert(
                team_id: teamId.uuidString,
                name: name,
                jersey_number: jerseyNumber,
                position: position
            ))
            .select()
            .single()
            .execute()
            .value
        
        return athlete
    }
    
    func updateAthlete(id: UUID, name: String, jerseyNumber: String, position: String) async throws {
        try await client.from("athletes")
            .update(AthleteUpdate(name: name, jersey_number: jerseyNumber, position: position))
            .eq("id", value: id)
            .execute()
    }
    
    func deactivateAthlete(id: UUID) async throws {
        try await client.from("athletes")
            .update(AthleteUpdate(active: false))
            .eq("id", value: id)
            .execute()
    }
    
    // MARK: - Sessions
    
    func getSessions(teamId: UUID, since: Date) async throws -> [CaptureSession] {
        let formatter = ISO8601DateFormatter()
        let dateStr = formatter.string(from: since)
        
        let sessions: [CaptureSession] = try await client.from("sessions")
            .select()
            .eq("team_id", value: teamId)
            .gte("date", value: dateStr)
            .order("date", ascending: false)
            .execute()
            .value
        
        return sessions
    }
    
    func createSession(teamId: UUID, date: Date, state: SessionState, userId: UUID) async throws -> CaptureSession {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let session: CaptureSession = try await client.from("sessions")
            .insert(SessionInsert(
                team_id: teamId.uuidString,
                date: formatter.string(from: date),
                state: state.rawValue,
                created_by: userId.uuidString
            ))
            .select()
            .single()
            .execute()
            .value
        
        return session
    }
    
    // MARK: - Captures
    
    func getCaptures(sessionIds: [UUID]) async throws -> [Capture] {
        let captures: [Capture] = try await client.from("captures")
            .select()
            .in("session_id", values: sessionIds.map { $0.uuidString })
            .execute()
            .value
        
        return captures
    }
    
    func getCapturesForAthlete(athleteId: UUID, sessionIds: [UUID]) async throws -> [Capture] {
        let captures: [Capture] = try await client.from("captures")
            .select()
            .eq("athlete_id", value: athleteId)
            .in("session_id", values: sessionIds.map { $0.uuidString })
            .order("created_at", ascending: true)
            .execute()
            .value
        
        return captures
    }
    
    func insertCapture(sessionId: UUID, athleteId: UUID, metrics: ModelMetrics) async throws {
        try await client.from("captures")
            .insert(CaptureInsert(
                session_id: sessionId.uuidString,
                athlete_id: athleteId.uuidString,
                knee_valgus_deg: metrics.kneeValgusDeg,
                knee_flexion_deg: metrics.kneeFlexionDeg,
                trunk_lean_deg: metrics.trunkLeanDeg,
                less_score: metrics.lessScore,
                risk_level: metrics.riskLevel,
                asymmetry_index: metrics.asymmetryIndex,
                model_version: "mock-v1"
            ))
            .execute()
    }
}
