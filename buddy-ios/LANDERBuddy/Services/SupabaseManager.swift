import Foundation

/// Mock data manager — replaces Supabase for now.
/// All data is stored in memory. No backend needed.
class SupabaseManager {
    static let shared = SupabaseManager()
    
    // In-memory storage
    private var team: Team?
    private var athletes: [Athlete] = []
    private var sessions: [CaptureSession] = []
    private var captures: [Capture] = []
    
    private init() {
        // Seed with demo data
        let teamId = UUID()
        team = Team(
            id: teamId,
            name: "Demo Team",
            thresholds: .defaults,
            createdAt: Date()
        )
        
        // Demo athletes
        let a1 = Athlete(id: UUID(), teamId: teamId, name: "Sarah Johnson", jerseyNumber: "7", position: "Forward", active: true, createdAt: Date())
        let a2 = Athlete(id: UUID(), teamId: teamId, name: "Maria Garcia", jerseyNumber: "12", position: "Midfielder", active: true, createdAt: Date())
        let a3 = Athlete(id: UUID(), teamId: teamId, name: "Emily Chen", jerseyNumber: "3", position: "Defender", active: true, createdAt: Date())
        let a4 = Athlete(id: UUID(), teamId: teamId, name: "Alex Williams", jerseyNumber: "21", position: "Goalkeeper", active: true, createdAt: Date())
        athletes = [a1, a2, a3, a4]
        
        // Generate some demo session history (last 4 weeks)
        for weeksAgo in (0..<4).reversed() {
            let freshDate = Calendar.current.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date())!
            let fatiguedDate = Calendar.current.date(byAdding: .day, value: 1, to: freshDate)!
            
            let freshSession = CaptureSession(id: UUID(), teamId: teamId, date: freshDate, state: .fresh, notes: nil, createdBy: nil, createdAt: freshDate)
            let fatiguedSession = CaptureSession(id: UUID(), teamId: teamId, date: fatiguedDate, state: .fatigued, notes: nil, createdBy: nil, createdAt: fatiguedDate)
            sessions.append(freshSession)
            sessions.append(fatiguedSession)
            
            // Generate captures for each athlete
            for athlete in athletes {
                let freshMetrics = CVModelService.mockMetricsSync(sessionState: .fresh)
                let fatiguedMetrics = CVModelService.mockMetricsSync(sessionState: .fatigued)
                
                captures.append(Capture(
                    id: UUID(), sessionId: freshSession.id, athleteId: athlete.id,
                    kneeValgusDeg: freshMetrics.kneeValgusDeg,
                    kneeFlexionDeg: freshMetrics.kneeFlexionDeg,
                    trunkLeanDeg: freshMetrics.trunkLeanDeg,
                    lessScore: freshMetrics.lessScore,
                    riskLevel: freshMetrics.riskLevel,
                    asymmetryIndex: freshMetrics.asymmetryIndex,
                    vulnerabilityScore: nil, fatigueCategory: nil,
                    modelVersion: "mock", createdAt: freshDate
                ))
                captures.append(Capture(
                    id: UUID(), sessionId: fatiguedSession.id, athleteId: athlete.id,
                    kneeValgusDeg: fatiguedMetrics.kneeValgusDeg,
                    kneeFlexionDeg: fatiguedMetrics.kneeFlexionDeg,
                    trunkLeanDeg: fatiguedMetrics.trunkLeanDeg,
                    lessScore: fatiguedMetrics.lessScore,
                    riskLevel: fatiguedMetrics.riskLevel,
                    asymmetryIndex: fatiguedMetrics.asymmetryIndex,
                    vulnerabilityScore: nil, fatigueCategory: nil,
                    modelVersion: "mock", createdAt: fatiguedDate
                ))
            }
        }
    }
    
    // MARK: - Team
    
    func getTeam() async throws -> Team? { team }
    
    func createTeam(name: String) async throws -> Team {
        let t = Team(id: UUID(), name: name, thresholds: .defaults, createdAt: Date())
        team = t
        return t
    }
    
    func updateTeam(id: UUID, name: String, thresholds: Thresholds) async throws {
        team?.name = name
        team?.thresholds = thresholds
    }
    
    // MARK: - Profile
    
    func updateProfile(userId: UUID, teamId: UUID, role: UserRole) async throws {}
    
    // MARK: - Athletes
    
    func getAthletes(teamId: UUID) async throws -> [Athlete] {
        athletes.filter { $0.active }
    }
    
    func addAthlete(teamId: UUID, name: String, jerseyNumber: String, position: String) async throws -> Athlete {
        let a = Athlete(id: UUID(), teamId: teamId, name: name, jerseyNumber: jerseyNumber, position: position, active: true, createdAt: Date())
        athletes.append(a)
        return a
    }
    
    func updateAthlete(id: UUID, name: String, jerseyNumber: String, position: String) async throws {
        if let i = athletes.firstIndex(where: { $0.id == id }) {
            athletes[i].name = name
            athletes[i].jerseyNumber = jerseyNumber
            athletes[i].position = position
        }
    }
    
    func deactivateAthlete(id: UUID) async throws {
        if let i = athletes.firstIndex(where: { $0.id == id }) {
            athletes[i].active = false
        }
    }
    
    // MARK: - Sessions
    
    func getSessions(teamId: UUID, since: Date) async throws -> [CaptureSession] {
        sessions.filter { $0.date >= since }.sorted { $0.date > $1.date }
    }
    
    func createSession(teamId: UUID, date: Date, state: SessionState, userId: UUID) async throws -> CaptureSession {
        let s = CaptureSession(id: UUID(), teamId: teamId, date: date, state: state, notes: nil, createdBy: userId, createdAt: Date())
        sessions.append(s)
        return s
    }
    
    // MARK: - Captures
    
    func getCaptures(sessionIds: [UUID]) async throws -> [Capture] {
        captures.filter { sessionIds.contains($0.sessionId) }
    }
    
    func getCapturesForAthlete(athleteId: UUID, sessionIds: [UUID]) async throws -> [Capture] {
        captures.filter { $0.athleteId == athleteId && sessionIds.contains($0.sessionId) }
    }
    
    func insertCapture(sessionId: UUID, athleteId: UUID, metrics: ModelMetrics) async throws {
        let c = Capture(
            id: UUID(), sessionId: sessionId, athleteId: athleteId,
            kneeValgusDeg: metrics.kneeValgusDeg,
            kneeFlexionDeg: metrics.kneeFlexionDeg,
            trunkLeanDeg: metrics.trunkLeanDeg,
            lessScore: metrics.lessScore,
            riskLevel: metrics.riskLevel,
            asymmetryIndex: metrics.asymmetryIndex,
            vulnerabilityScore: nil, fatigueCategory: nil,
            modelVersion: "mock", createdAt: Date()
        )
        captures.append(c)
    }
}
