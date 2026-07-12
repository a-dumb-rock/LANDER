import Foundation
import Supabase

/// Centralized Supabase client for auth and database operations.
class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        // These should be set in Config.swift or via environment
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
            .insert(["name": name])
            .select()
            .single()
            .execute()
            .value
        
        return team
    }
    
    func updateTeam(id: UUID, name: String, thresholds: Thresholds) async throws {
        let encoder = JSONEncoder()
        let thresholdsData = try encoder.encode(thresholds)
        let thresholdsDict = try JSONSerialization.jsonObject(with: thresholdsData) as! [String: Any]
        
        try await client.from("teams")
            .update([
                "name": AnyJSON.string(name),
                "thresholds": AnyJSON(thresholdsDict)
            ])
            .eq("id", value: id)
            .execute()
    }
    
    // MARK: - Profile
    
    func updateProfile(userId: UUID, teamId: UUID, role: UserRole) async throws {
        try await client.from("profiles")
            .update([
                "team_id": AnyJSON.string(teamId.uuidString),
                "role": AnyJSON.string(role.rawValue)
            ])
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
            .insert([
                "team_id": teamId.uuidString,
                "name": name,
                "jersey_number": jerseyNumber,
                "position": position
            ])
            .select()
            .single()
            .execute()
            .value
        
        return athlete
    }
    
    func updateAthlete(id: UUID, name: String, jerseyNumber: String, position: String) async throws {
        try await client.from("athletes")
            .update([
                "name": AnyJSON.string(name),
                "jersey_number": AnyJSON.string(jerseyNumber),
                "position": AnyJSON.string(position)
            ])
            .eq("id", value: id)
            .execute()
    }
    
    func deactivateAthlete(id: UUID) async throws {
        try await client.from("athletes")
            .update(["active": AnyJSON.bool(false)])
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
            .insert([
                "team_id": teamId.uuidString,
                "date": formatter.string(from: date),
                "state": state.rawValue,
                "created_by": userId.uuidString
            ])
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
            .insert([
                "session_id": AnyJSON.string(sessionId.uuidString),
                "athlete_id": AnyJSON.string(athleteId.uuidString),
                "knee_valgus_deg": AnyJSON.double(metrics.kneeValgusDeg),
                "knee_flexion_deg": AnyJSON.double(metrics.kneeFlexionDeg),
                "trunk_lean_deg": AnyJSON.double(metrics.trunkLeanDeg),
                "less_score": AnyJSON.double(metrics.lessScore),
                "risk_level": AnyJSON.string(metrics.riskLevel),
                "asymmetry_index": AnyJSON.double(metrics.asymmetryIndex),
                "model_version": AnyJSON.string("mock-v1")
            ])
            .execute()
    }
}
