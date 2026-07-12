import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        TabView {
            ReadinessBoardView()
                .tabItem {
                    Label("Readiness", systemImage: "heart.text.square")
                }
            
            CaptureSessionView()
                .tabItem {
                    Label("Capture", systemImage: "camera.fill")
                }
            
            RosterView()
                .tabItem {
                    Label("Roster", systemImage: "person.3.fill")
                }
            
            SessionsListView()
                .tabItem {
                    Label("Sessions", systemImage: "calendar")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Color.brand)
        .task {
            await appState.loadTeamData()
        }
    }
}
