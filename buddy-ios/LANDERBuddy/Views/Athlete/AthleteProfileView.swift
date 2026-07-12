import SwiftUI

struct AthleteProfileView: View {
    @EnvironmentObject var appState: AppState
    let athleteId: UUID
    
    private var readiness: AthleteReadiness? {
        appState.readinessList.first { $0.athlete.id == athleteId }
    }
    
    private var athlete: Athlete? {
        appState.athletes.first { $0.id == athleteId }
    }
    
    private var athleteCaptures: [Capture] {
        appState.captures.filter { $0.athleteId == athleteId }
    }
    
    var body: some View {
        ScrollView {
            if let readiness = readiness, let athlete = athlete {
                VStack(spacing: 16) {
                    // Header
                    header(athlete: athlete, readiness: readiness)
                    
                    // Stats grid
                    statsGrid(readiness: readiness)
                    
                    // Recommendation
                    recommendationCard(readiness: readiness)
                    
                    // Trend charts
                    trendSection
                    
                    // History
                    historySection
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(athlete?.name ?? "Athlete")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header
    
    private func header(athlete: Athlete, readiness: AthleteReadiness) -> some View {
        HStack(spacing: 12) {
            Text("#\(athlete.jerseyNumber.isEmpty ? "—" : athlete.jerseyNumber)")
                .font(.title2.weight(.bold))
                .frame(width: 56, height: 56)
                .background(Color.brand.opacity(0.1))
                .foregroundColor(.brand)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(athlete.name)
                    .font(.title3.weight(.bold))
                Text(athlete.position.isEmpty ? "No position" : athlete.position)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            StatusBadge(status: readiness.status)
        }
    }
    
    // MARK: - Stats
    
    private func statsGrid(readiness: AthleteReadiness) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 12) {
            StatCard(title: "Valgus", value: readiness.latestValgus.map { "\(String(format: "%.1f", $0))°" } ?? "—")
            StatCard(title: "Delta",
                     value: readiness.fatigueDeltaPct.map { "\($0 > 0 ? "+" : "")\(Int($0))%" } ?? "—",
                     color: (readiness.fatigueDeltaPct ?? 0) > 20 ? .statusRed : (readiness.fatigueDeltaPct ?? 0) > 10 ? .statusYellow : .statusGreen)
            StatCard(title: "Trend", value: "\(readiness.trend.symbol) \(readiness.trend.label)")
            StatCard(title: "Weeks", value: "\(readiness.weeksOfData)")
        }
    }
    
    // MARK: - Recommendation
    
    private func recommendationCard(readiness: AthleteReadiness) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendation")
                .font(.subheadline.weight(.semibold))
            Text(readiness.recommendation)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
    
    // MARK: - Trends
    
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trends")
                .font(.headline)
            
            if athleteCaptures.isEmpty {
                Text("No capture data yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                // Simple sparkline-style chart using native SwiftUI
                VStack(spacing: 16) {
                    MiniChart(
                        title: "Knee Valgus (°)",
                        values: athleteCaptures.compactMap { $0.kneeValgusDeg },
                        color: .statusRed
                    )
                    MiniChart(
                        title: "Knee Flexion (°)",
                        values: athleteCaptures.compactMap { $0.kneeFlexionDeg },
                        color: .blue
                    )
                    MiniChart(
                        title: "LESS Score",
                        values: athleteCaptures.compactMap { $0.lessScore },
                        color: .orange
                    )
                }
            }
        }
    }
    
    // MARK: - History
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session History")
                .font(.headline)
            
            if athleteCaptures.isEmpty {
                Text("No sessions recorded yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(athleteCaptures.sorted(by: { $0.createdAt > $1.createdAt })) { capture in
                    let session = appState.sessions.first { $0.id == capture.sessionId }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capture.createdAt, style: .date)
                                .font(.caption.weight(.medium))
                            Text(session?.state.shortLabel ?? "")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(session?.state == .fresh ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                                .foregroundColor(session?.state == .fresh ? .blue : .orange)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(String(format: "%.1f", capture.kneeValgusDeg ?? 0))° valgus")
                                .font(.caption)
                            Text("\(String(format: "%.1f", capture.kneeFlexionDeg ?? 0))° flexion")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
    }
}

struct MiniChart: View {
    let title: String
    let values: [Double]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            
            if values.count < 2 {
                Text("Not enough data")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                // Simple line chart using GeometryReader
                GeometryReader { geo in
                    let minVal = values.min()!
                    let maxVal = values.max()!
                    let range = max(maxVal - minVal, 1)
                    
                    Path { path in
                        for (i, val) in values.enumerated() {
                            let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                            let y = geo.size.height * (1 - CGFloat((val - minVal) / range))
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, lineWidth: 2)
                }
                .frame(height: 50)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
