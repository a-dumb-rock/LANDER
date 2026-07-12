import Foundation
import Supabase

/// Manages authentication state.
@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userId: UUID?
    @Published var isLoading = false
    @Published var error: String?
    
    private let supabase = SupabaseManager.shared.client
    
    func checkSession() async {
        do {
            let session = try await supabase.auth.session
            isAuthenticated = true
            userId = session.user.id
        } catch {
            isAuthenticated = false
            userId = nil
        }
    }
    
    func signUp(email: String, password: String, fullName: String, teamName: String, role: UserRole) async {
        isLoading = true
        error = nil
        
        do {
            // 1. Sign up
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(fullName)]
            )
            
            let user = response.user
            userId = user.id
            
            // 2. Create team
            let team = try await SupabaseManager.shared.createTeam(name: teamName)
            
            // 3. Link profile to team
            try await SupabaseManager.shared.updateProfile(
                userId: user.id,
                teamId: team.id,
                role: role
            )
            
            isAuthenticated = true
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func logIn(email: String, password: String) async {
        isLoading = true
        error = nil
        
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            userId = session.user.id
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signOut() async {
        try? await supabase.auth.signOut()
        isAuthenticated = false
        userId = nil
    }
}
