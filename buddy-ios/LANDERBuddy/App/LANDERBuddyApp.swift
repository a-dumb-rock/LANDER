import SwiftUI

@main
struct LANDERBuddyApp: App {
    @State private var authManager = AuthManager()
    @State private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                        .environment(authManager)
                        .environment(appState)
                } else {
                    LoginView()
                        .environment(authManager)
                }
            }
            .task {
                await authManager.checkSession()
            }
        }
    }
}
