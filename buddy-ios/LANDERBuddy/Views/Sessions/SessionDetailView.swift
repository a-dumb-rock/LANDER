import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var appState: AppState
    let session: CaptureSession
    
    private var sessionCaptures: [Capture] {
        appState.captures.filter { $0.sessionId == session.id }
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Date")
                    Spacer()
                    Text(session.date, style: .date)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Type")
                    Spacer()
                    Text(session.state.shortLabel)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(session.state == .fresh ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                        .foregroundColor(session.state == .fresh ? .blue : .orange)
                        .clipShape(Capsule())
                }
                HStack {
                    Text("Athletes")
                    Spacer()
                    Text("\(sessionCaptures.count)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Results") {
                if sessionCaptures.isEmpty {
                    Text("No captures in this session.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sessionCaptures) { capture in
                        let athlete = appState.athletes.first { $0.id == capture.athleteId }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(athlete?.name ?? "Unknown")
                                    .font(.subheadline.weight(.semibold))
                                Text("#\(athlete?.jerseyNumber ?? "—") · \(athlete?.position ?? "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(String(format: "%.1f", capture.kneeValgusDeg ?? 0))° valgus")
                                    .font(.caption)
                                Text("\(String(format: "%.1f", capture.kneeFlexionDeg ?? 0))° flexion")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("LESS: \(Int(capture.lessScore ?? 0))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Session Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
