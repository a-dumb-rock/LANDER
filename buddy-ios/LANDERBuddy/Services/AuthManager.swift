import SwiftUI
import Observation

/// Mock auth manager — auto-logs in for demo purposes.
@MainActor
@Observable
class AuthManager {
    var isAuthenticated = true  // Auto-authenticated for demo
    var userId: UUID? = UUID()
    var isLoading = false
    var error: String?
    
    func checkSession() async {
        // Auto-authenticated in demo mode
        isAuthenticated = true
        userId = UUID()
    }
    
    func signUp(email: String, password: String, fullName: String, teamName: String, role: UserRole) async {
        isLoading = true
        // In demo mode, just mark as authenticated
        try? await Task.sleep(nanoseconds: 500_000_000)
        isAuthenticated = true
        isLoading = false
    }
    
    func logIn(email: String, password: String) async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 500_000_000)
        isAuthenticated = true
        isLoading = false
    }
    
    func signOut() async {
        isAuthenticated = false
        userId = nil
    }
}
