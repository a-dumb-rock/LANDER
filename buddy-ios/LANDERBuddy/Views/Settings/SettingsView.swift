import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @Environment(AuthManager.self) var authManager
    
    @State private var teamName: String = ""
    @State private var thresholds: Thresholds = .defaults
    @State private var isSaving = false
    @State private var saved = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Team
                Section("Team") {
                    TextField("Team name", text: $teamName)
                }
                
                // Thresholds - Valgus
                Section("Knee Valgus Thresholds (degrees)") {
                    HStack {
                        Text("Yellow (caution)")
                        Spacer()
                        TextField("5", value: $thresholds.valgusYellowDeg, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Red (high risk)")
                        Spacer()
                        TextField("10", value: $thresholds.valgusRedDeg, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // Thresholds - Flexion
                Section("Knee Flexion Thresholds (lower = worse)") {
                    HStack {
                        Text("Yellow")
                        Spacer()
                        TextField("45", value: $thresholds.flexionYellowDeg, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Red")
                        Spacer()
                        TextField("30", value: $thresholds.flexionRedDeg, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // Thresholds - Delta
                Section("Fatigue Delta Thresholds (% worsening)") {
                    HStack {
                        Text("Yellow")
                        Spacer()
                        TextField("10", value: $thresholds.deltaYellowPct, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Red")
                        Spacer()
                        TextField("20", value: $thresholds.deltaRedPct, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // Baseline
                Section("Baseline") {
                    HStack {
                        Text("Fresh sessions to average")
                        Spacer()
                        TextField("3", value: $thresholds.baselineNSessions, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // CV Model
                Section("CV Model") {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text(Config.useMockModel ? "Mock" : "Real")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("API URL")
                        Spacer()
                        Text(Config.cvModelURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Save
                Section {
                    Button(action: { Task { await save() } }) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text(saved ? "Saved!" : "Save Settings")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .foregroundColor(.brand)
                }
                
                // Sign out
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await authManager.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                teamName = appState.team?.name ?? ""
                thresholds = appState.team?.thresholds ?? .defaults
            }
        }
    }
    
    private func save() async {
        guard let teamId = appState.team?.id else { return }
        isSaving = true
        
        do {
            try await SupabaseManager.shared.updateTeam(
                id: teamId, name: teamName, thresholds: thresholds
            )
            saved = true
            await appState.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        } catch {
            appState.error = error.localizedDescription
        }
        
        isSaving = false
    }
}
