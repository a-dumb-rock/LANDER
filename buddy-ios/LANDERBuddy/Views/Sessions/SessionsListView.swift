import SwiftUI

struct SessionsListView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        NavigationStack {
            List {
                if appState.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "calendar",
                        description: Text("Run your first capture session to start.")
                    )
                } else {
                    ForEach(appState.sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRow(session: session)
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .refreshable {
                await appState.refresh()
            }
        }
    }
}

struct SessionRow: View {
    let session: CaptureSession
    
    var body: some View {
        HStack(spacing: 12) {
            Text(session.state == .fresh ? "F" : "T")
                .font(.caption.weight(.bold))
                .frame(width: 32, height: 32)
                .background(session.state == .fresh ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                .foregroundColor(session.state == .fresh ? .blue : .orange)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.date, style: .date)
                    .font(.subheadline.weight(.medium))
                Text(session.state.shortLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(session.state == .fresh ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                    .foregroundColor(session.state == .fresh ? .blue : .orange)
                    .clipShape(Capsule())
            }
        }
    }
}
