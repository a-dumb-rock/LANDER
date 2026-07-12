import SwiftUI

struct ReadinessBoardView: View {
    @EnvironmentObject var appState: AppState
    
    private var counts: [ReadinessStatus: Int] {
        Dictionary(grouping: appState.readinessList, by: { $0.status })
            .mapValues { $0.count }
    }
    
    private var alerts: [AthleteReadiness] {
        appState.readinessList.filter { $0.status == .red || ($0.status == .yellow && $0.trend == .worsening) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary bar
                    SummaryBar(counts: counts, alertCount: alerts.count)
                        .padding(.horizontal)
                    
                    // Athlete list
                    if appState.readinessList.isEmpty {
                        EmptyRosterCard()
                            .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.readinessList) { readiness in
                                NavigationLink(destination: AthleteProfileView(athleteId: readiness.athlete.id)) {
                                    AthleteReadinessRow(readiness: readiness)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Tip
                    TipCard()
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                .padding(.vertical)
            }
            .navigationTitle("Readiness Board")
            .refreshable {
                await appState.refresh()
            }
            .overlay {
                if appState.isLoading && appState.readinessList.isEmpty {
                    ProgressView("Loading team data...")
                }
            }
        }
    }
}

// MARK: - Subviews

struct SummaryBar: View {
    let counts: [ReadinessStatus: Int]
    let alertCount: Int
    
    var body: some View {
        HStack(spacing: 16) {
            StatusCount(status: .green, count: counts[.green] ?? 0)
            StatusCount(status: .yellow, count: counts[.yellow] ?? 0)
            StatusCount(status: .red, count: counts[.red] ?? 0)
            
            Spacer()
            
            if alertCount > 0 {
                Text("\(alertCount) need attention")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.statusRedBg)
                    .foregroundColor(.statusRedText)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct StatusCount: View {
    let status: ReadinessStatus
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            StatusDot(status: status, size: 10)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
        }
    }
}

struct AthleteReadinessRow: View {
    let readiness: AthleteReadiness
    
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: readiness.status, size: 14)
            
            // Jersey number
            Text("#\(readiness.athlete.jerseyNumber.isEmpty ? "—" : readiness.athlete.jerseyNumber)")
                .font(.caption.weight(.bold))
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())
            
            // Name & position
            VStack(alignment: .leading, spacing: 2) {
                Text(readiness.athlete.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(readiness.athlete.position.isEmpty ? "No position" : readiness.athlete.position)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Metrics
            VStack(alignment: .trailing, spacing: 2) {
                if let pct = readiness.fatigueDeltaPct {
                    Text("\(pct > 0 ? "+" : "")\(Int(pct))%")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(pct > 20 ? .statusRed : pct > 10 ? .statusYellow : .statusGreen)
                } else if let valgus = readiness.latestValgus {
                    Text("\(String(format: "%.1f", valgus))°")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
                
                if readiness.trend != .unknown {
                    TrendBadge(trend: readiness.trend)
                }
            }
            
            StatusBadge(status: readiness.status)
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

struct EmptyRosterCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No athletes yet")
                .font(.headline)
            Text("Add athletes in the Roster tab, then run a capture session.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TipCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.blue)
            Text("Use the same jump and the same camera position each time so comparisons stay valid. Film once fresh (warm-up) and once fatigued (end of practice).")
                .font(.caption)
                .foregroundColor(.blue.opacity(0.8))
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
