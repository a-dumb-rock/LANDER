import SwiftUI

@main
struct LANDERBuddyApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                        .environmentObject(authManager)
                        .environmentObject(appState)
                } else {
                    LoginView()
                        .environmentObject(authManager)
                }
            }
            .task {
                await authManager.checkSession()
            }
        }
    }
}
