import SwiftUI
import Observation

/// Central app state that holds the current team, athletes, and readiness data.
@MainActor
@Observable
class AppState {
    var team: Team?
    var athletes: [Athlete] = []
    var sessions: [CaptureSession] = []
    var captures: [Capture] = []
    var readinessList: [AthleteReadiness] = []
    var isLoading = false
    var error: String?
    
    private let db = SupabaseManager.shared
    
    func loadTeamData() async {
        isLoading = true
        error = nil
        
        do {
            // Load team
            team = try await db.getTeam()
            
            guard let teamId = team?.id else {
                isLoading = false
                return
            }
            
            // Load athletes
            athletes = try await db.getAthletes(teamId: teamId)
            
            // Load sessions (last 8 weeks)
            let eightWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date())!
            sessions = try await db.getSessions(teamId: teamId, since: eightWeeksAgo)
            
            // Load captures for those sessions
            let sessionIds = sessions.map { $0.id }
            if !sessionIds.isEmpty {
                captures = try await db.getCaptures(sessionIds: sessionIds)
            } else {
                captures = []
            }
            
            // Compute readiness for each athlete
            let thresholds = team?.thresholds ?? Thresholds.defaults
            readinessList = DeltaEngine.computeTeamReadiness(
                athletes: athletes,
                sessions: sessions,
                captures: captures,
                thresholds: thresholds
            )
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadTeamData()
    }
}
