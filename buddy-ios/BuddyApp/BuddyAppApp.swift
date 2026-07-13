import SwiftUI
import AuthenticationServices

// MARK: - Models

enum ReadinessStatus: String, CaseIterable {
    case green = "Good"
    case yellow = "Caution"
    case red = "At Risk"
    var color: Color {
        switch self {
        case .green: return Color(red: 0.2, green: 0.78, blue: 0.4)
        case .yellow: return Color(red: 0.95, green: 0.7, blue: 0.1)
        case .red: return Color(red: 0.93, green: 0.26, blue: 0.26)
        }
    }
    var bgColor: Color {
        switch self {
        case .green: return Color(red: 0.2, green: 0.78, blue: 0.4).opacity(0.12)
        case .yellow: return Color(red: 0.95, green: 0.7, blue: 0.1).opacity(0.12)
        case .red: return Color(red: 0.93, green: 0.26, blue: 0.26).opacity(0.12)
        }
    }
}

enum TrendDirection: String {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"
    var icon: String {
        switch self {
        case .improving: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.up.right"
        }
    }
    var color: Color {
        switch self {
        case .improving: return Color(red: 0.2, green: 0.78, blue: 0.4)
        case .stable: return .secondary
        case .declining: return Color(red: 0.93, green: 0.26, blue: 0.26)
        }
    }
}


struct Thresholds {
    var yellowDelta: Double = 8.0
    var redDelta: Double = 15.0
}

struct Athlete: Identifiable {
    let id: UUID
    var name: String
    var jerseyNumber: Int
    var position: String
    var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

struct CaptureSession: Identifiable {
    let id: UUID
    let date: Date
    let isFresh: Bool
    let athleteIDs: [UUID]
    var metrics: [UUID: ModelMetrics]
}

struct ModelMetrics: Identifiable {
    let id = UUID()
    let kneeFlexionAngle: Double
    let valgusAngle: Double
    let landingForce: Double
    let stabilizationTime: Double
    let symmetryIndex: Double
    var compositeScore: Double {
        let flex = min(max((kneeFlexionAngle - 30) / 40, 0), 1) * 100
        let valg = min(max((15 - valgusAngle) / 15, 0), 1) * 100
        let force = min(max((5 - landingForce) / 3, 0), 1) * 100
        let stab = min(max((1.5 - stabilizationTime) / 1.0, 0), 1) * 100
        let sym = symmetryIndex
        return (flex + valg + force + stab + sym) / 5.0
    }
}

struct AthleteReadiness: Identifiable {
    let id: UUID
    let athlete: Athlete
    let currentScore: Double
    let baselineScore: Double
    let delta: Double
    let status: ReadinessStatus
    let trend: TrendDirection
    let history: [Double]
}


// MARK: - Data Engine

@Observable
class DataEngine {
    var athletes: [Athlete] = []
    var sessions: [CaptureSession] = []
    var thresholds = Thresholds()
    var isSignedIn = false
    var userName: String = ""
    var teamName: String = ""

    init() { seedDemoData() }

    func seedDemoData() {
        athletes = [
            Athlete(id: UUID(), name: "Maya Johnson", jerseyNumber: 7, position: "Forward"),
            Athlete(id: UUID(), name: "Carlos Rivera", jerseyNumber: 12, position: "Midfielder"),
            Athlete(id: UUID(), name: "Aisha Patel", jerseyNumber: 3, position: "Defender"),
            Athlete(id: UUID(), name: "Jake Thompson", jerseyNumber: 21, position: "Goalkeeper")
        ]
        let calendar = Calendar.current
        let today = Date()
        var allSessions: [CaptureSession] = []
        for weekOffset in (0..<4).reversed() {
            for dayOffset in [0, 3] {
                let date = calendar.date(byAdding: .day, value: -(weekOffset * 7 + dayOffset), to: today)!
                let isFresh = dayOffset == 0
                var metrics: [UUID: ModelMetrics] = [:]
                for (index, athlete) in athletes.enumerated() {
                    let fatigueFactor = isFresh ? 0.0 : Double(weekOffset) * 0.5 + Double(index) * 0.3
                    metrics[athlete.id] = generateMetrics(fatigueFactor: fatigueFactor, athleteIndex: index)
                }
                allSessions.append(CaptureSession(id: UUID(), date: date, isFresh: isFresh, athleteIDs: athletes.map { $0.id }, metrics: metrics))
            }
        }
        sessions = allSessions.sorted { $0.date < $1.date }
    }

    private func generateMetrics(fatigueFactor: Double, athleteIndex: Int) -> ModelMetrics {
        let base = 45.0 + Double(athleteIndex) * 3
        return ModelMetrics(
            kneeFlexionAngle: base - fatigueFactor * 2 + Double.random(in: -2...2),
            valgusAngle: 5.0 + fatigueFactor * 1.5 + Double.random(in: -1...1),
            landingForce: 2.5 + fatigueFactor * 0.3 + Double.random(in: -0.2...0.2),
            stabilizationTime: 0.6 + fatigueFactor * 0.1 + Double.random(in: -0.05...0.05),
            symmetryIndex: 92.0 - fatigueFactor * 2 + Double.random(in: -1...1)
        )
    }

    func computeReadiness() -> [AthleteReadiness] {
        athletes.map { athlete in
            let athleteSessions = sessions.filter { $0.athleteIDs.contains(athlete.id) }
            let freshScores = athleteSessions.filter { $0.isFresh }.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let fatiguedScores = athleteSessions.filter { !$0.isFresh }.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let baseline = freshScores.isEmpty ? 80.0 : freshScores.reduce(0, +) / Double(freshScores.count)
            let current = fatiguedScores.last ?? baseline
            let delta = baseline - current
            let status: ReadinessStatus = delta >= thresholds.redDelta ? .red : delta >= thresholds.yellowDelta ? .yellow : .green
            let allScores = athleteSessions.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let trend: TrendDirection
            if allScores.count >= 3 {
                let diff = allScores.suffix(3).last! - allScores.suffix(3).first!
                trend = diff > 2 ? .improving : diff < -2 ? .declining : .stable
            } else { trend = .stable }
            return AthleteReadiness(id: athlete.id, athlete: athlete, currentScore: current, baselineScore: baseline, delta: delta, status: status, trend: trend, history: allScores)
        }.sorted { statusOrder($0.status) < statusOrder($1.status) }
    }

    private func statusOrder(_ s: ReadinessStatus) -> Int { s == .red ? 0 : s == .yellow ? 1 : 2 }
    func addAthlete(name: String, jerseyNumber: Int, position: String) { athletes.append(Athlete(id: UUID(), name: name, jerseyNumber: jerseyNumber, position: position)) }
    func removeAthlete(id: UUID) { athletes.removeAll { $0.id == id } }
    func runCapture(date: Date, isFresh: Bool, athleteIDs: [UUID]) {
        var metrics: [UUID: ModelMetrics] = [:]
        for (i, id) in athleteIDs.enumerated() { metrics[id] = generateMetrics(fatigueFactor: isFresh ? 0 : Double.random(in: 1...4), athleteIndex: i) }
        sessions.append(CaptureSession(id: UUID(), date: date, isFresh: isFresh, athleteIDs: athleteIDs, metrics: metrics))
        sessions.sort { $0.date < $1.date }
    }
}


// MARK: - App Entry

@main
struct BuddyAppApp: App {
    @State private var engine = DataEngine()
    var body: some Scene {
        WindowGroup {
            if engine.isSignedIn {
                MainTabView().environment(engine)
            } else {
                OnboardingView().environment(engine)
            }
        }
    }
}

// MARK: - Onboarding / Sign In

struct OnboardingView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.06, blue: 0.16), Color(red: 0.04, green: 0.12, blue: 0.28)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                // Logo
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.brand.opacity(0.15)).frame(width: 88, height: 88)
                        Image(systemName: "figure.run").font(.system(size: 36, weight: .medium)).foregroundStyle(Color.brand)
                    }
                    Text("LANDER").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Buddy").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.brand)
                }
                // Tagline
                VStack(spacing: 8) {
                    Text("Team Knee Readiness").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("Monitor landing mechanics, track fatigue,\nand keep your athletes safe.").font(.subheadline).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                }
                Spacer()
                // Sign in buttons
                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        engine.userName = "Athlete"
                        engine.teamName = "My Team"
                        withAnimation { engine.isSignedIn = true }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button(action: { withAnimation { engine.userName = "Coach"; engine.teamName = "My Team"; engine.isSignedIn = true } }) {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill").font(.title2)
                            Text("Continue with Google").font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: { withAnimation { engine.userName = "Trainer"; engine.teamName = "Demo Team"; engine.isSignedIn = true } }) {
                        Text("Skip for now").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                    }.padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    static let brand = Color(red: 14.0/255, green: 165.0/255, blue: 233.0/255)
    static let cardBg = Color(.systemBackground)
    static let subtleBg = Color(.secondarySystemBackground)
}


// MARK: - Main Tab View

struct MainTabView: View {
    var body: some View {
        TabView {
            ReadinessBoardView().tabItem { Label("Home", systemImage: "heart.text.clipboard") }
            CaptureFlowView().tabItem { Label("Capture", systemImage: "camera.fill") }
            RosterView().tabItem { Label("Roster", systemImage: "person.3.fill") }
            SessionsListView().tabItem { Label("History", systemImage: "clock.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }.tint(Color.brand)
    }
}

// MARK: - Readiness Board

struct ReadinessBoardView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary
                    let readiness = engine.computeReadiness()
                    let redCount = readiness.filter { $0.status == .red }.count
                    let yellowCount = readiness.filter { $0.status == .yellow }.count
                    let greenCount = readiness.filter { $0.status == .green }.count

                    HStack(spacing: 12) {
                        SummaryPill(count: greenCount, status: .green)
                        SummaryPill(count: yellowCount, status: .yellow)
                        SummaryPill(count: redCount, status: .red)
                        Spacer()
                    }.padding(.horizontal)

                    if redCount > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text("\(redCount) athlete\(redCount > 1 ? "s" : "") need\(redCount == 1 ? "s" : "") attention").font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Athletes
                    ForEach(readiness) { item in
                        NavigationLink(destination: AthleteDetailView(athleteID: item.athlete.id)) {
                            AthleteReadinessCard(item: item)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal)
                }.padding(.vertical)
            }
            .background(Color.subtleBg)
            .navigationTitle("Readiness")
        }
    }
}

struct SummaryPill: View {
    let count: Int; let status: ReadinessStatus
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 10, height: 10)
            Text("\(count)").font(.subheadline.weight(.bold))
            Text(status.rawValue).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(status.bgColor)
        .clipShape(Capsule())
    }
}

struct AthleteReadinessCard: View {
    let item: AthleteReadiness
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle().fill(item.athlete.avatarColor.opacity(0.15)).frame(width: 48, height: 48)
                Text("\(item.athlete.jerseyNumber)").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(item.athlete.avatarColor)
            }
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.athlete.name).font(.system(size: 16, weight: .semibold))
                Text(item.athlete.position).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Metrics
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%+.1f%%", -item.delta)).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(item.status.color)
                HStack(spacing: 3) {
                    Image(systemName: item.trend.icon).font(.system(size: 10))
                    Text(item.trend.rawValue).font(.system(size: 11))
                }.foregroundStyle(item.trend.color)
            }
            // Status badge
            Text(item.status.rawValue).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(item.status.bgColor)
                .foregroundStyle(item.status.color)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}


// MARK: - Athlete Detail

struct AthleteDetailView: View {
    @Environment(DataEngine.self) private var engine
    let athleteID: UUID
    var body: some View {
        let items = engine.computeReadiness()
        if let item = items.first(where: { $0.id == athleteID }) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(item.status.bgColor).frame(width: 64, height: 64)
                            Circle().fill(item.status.color).frame(width: 20, height: 20)
                        }
                        Text(item.status.rawValue).font(.headline).foregroundStyle(item.status.color)
                        Text(String(format: "Fatigue Delta: %+.1f%%", -item.delta)).font(.subheadline).foregroundStyle(.secondary)
                    }.padding().frame(maxWidth: .infinity).background(Color.cardBg).clipShape(RoundedRectangle(cornerRadius: 16))

                    // Chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance Trend").font(.subheadline.weight(.semibold))
                        MiniChartView(data: item.history, color: item.status.color).frame(height: 100)
                    }.padding().background(Color.cardBg).clipShape(RoundedRectangle(cornerRadius: 16))

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Baseline", value: String(format: "%.0f", item.baselineScore), icon: "target")
                        StatCard(title: "Current", value: String(format: "%.0f", item.currentScore), icon: "gauge.medium")
                        StatCard(title: "Trend", value: item.trend.rawValue, icon: item.trend.icon)
                        StatCard(title: "Sessions", value: "\(engine.sessions.filter { $0.athleteIDs.contains(athleteID) }.count)", icon: "calendar")
                    }

                    // Recent sessions
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Sessions").font(.subheadline.weight(.semibold))
                        let recent = engine.sessions.filter { $0.athleteIDs.contains(athleteID) }.sorted { $0.date > $1.date }.prefix(5)
                        ForEach(Array(recent)) { session in
                            if let m = session.metrics[athleteID] {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.date, style: .date).font(.subheadline)
                                        Text(session.isFresh ? "Fresh" : "Fatigued").font(.caption)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(session.isFresh ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(String(format: "%.0f", m.compositeScore)).font(.headline.monospacedDigit())
                                }
                                .padding(.vertical, 6)
                                if session.id != recent.last?.id { Divider() }
                            }
                        }
                    }.padding().background(Color.cardBg).clipShape(RoundedRectangle(cornerRadius: 16))
                }.padding()
            }
            .background(Color.subtleBg)
            .navigationTitle(item.athlete.name)
        } else { Text("Not found") }
    }
}

struct MiniChartView: View {
    let data: [Double]; var color: Color = Color.brand
    var body: some View {
        GeometryReader { geo in
            if data.count > 1 {
                let mn = (data.min() ?? 0) - 5, mx = (data.max() ?? 100) + 5, rng = mx - mn
                let step = geo.size.width / CGFloat(data.count - 1)
                // Fill
                Path { p in
                    for (i, v) in data.enumerated() {
                        let x = CGFloat(i) * step, y = geo.size.height - CGFloat((v - mn) / rng) * geo.size.height
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                // Line
                Path { p in
                    for (i, v) in data.enumerated() {
                        let x = CGFloat(i) * step, y = geo.size.height - CGFloat((v - mn) / rng) * geo.size.height
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(color, lineWidth: 2.5)
            } else { Text("Not enough data").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StatCard: View {
    let title: String; let value: String; var icon: String = "chart.bar"
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.brand)
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(14)
        .background(Color.cardBg).clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
    }
}


// MARK: - Capture Flow

struct CaptureFlowView: View {
    @Environment(DataEngine.self) private var engine
    @State private var captureDate = Date()
    @State private var isFresh = true
    @State private var selectedAthletes: Set<UUID> = []
    @State private var isProcessing = false
    @State private var showComplete = false
    var body: some View {
        NavigationStack {
            Form {
                Section { DatePicker("Date", selection: $captureDate, displayedComponents: .date)
                    Picker("Condition", selection: $isFresh) {
                        Text("Fresh (Warm-up)").tag(true)
                        Text("Fatigued (Post-Practice)").tag(false)
                    }
                } header: { Text("Session Info") }
                Section {
                    ForEach(engine.athletes) { a in
                        Button { if selectedAthletes.contains(a.id) { selectedAthletes.remove(a.id) } else { selectedAthletes.insert(a.id) } } label: {
                            HStack {
                                ZStack { Circle().fill(a.avatarColor.opacity(0.15)).frame(width: 32, height: 32); Text("\(a.jerseyNumber)").font(.caption.bold()).foregroundStyle(a.avatarColor) }
                                Text(a.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedAthletes.contains(a.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand) }
                            }
                        }
                    }
                } header: { Text("Athletes (\(selectedAthletes.count) selected)") }
                Section {
                    Button { isProcessing = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { engine.runCapture(date: captureDate, isFresh: isFresh, athleteIDs: Array(selectedAthletes)); isProcessing = false; showComplete = true } } label: {
                        HStack { Spacer()
                            if isProcessing { ProgressView().padding(.trailing, 6); Text("Analyzing...") }
                            else { Image(systemName: "bolt.fill"); Text("Analyze Landing") }
                            Spacer()
                        }.font(.headline).foregroundStyle(.white).padding(.vertical, 6)
                    }.listRowBackground(selectedAthletes.isEmpty ? Color.gray : Color.brand)
                    .disabled(selectedAthletes.isEmpty || isProcessing)
                }
            }
            .navigationTitle("New Capture")
            .alert("Session Complete", isPresented: $showComplete) { Button("Done") { selectedAthletes.removeAll() } } message: { Text("Processed \(selectedAthletes.count) athlete(s). Check the Readiness board for updates.") }
        }
    }
}


// MARK: - Roster

struct RosterView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showAdd = false
    @State private var newName = ""; @State private var newJersey = ""; @State private var newPosition = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(engine.athletes) { a in
                    HStack(spacing: 14) {
                        ZStack { Circle().fill(a.avatarColor.opacity(0.15)).frame(width: 44, height: 44); Text("\(a.jerseyNumber)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(a.avatarColor) }
                        VStack(alignment: .leading, spacing: 2) { Text(a.name).font(.body.weight(.medium)); Text(a.position).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }.onDelete { idx in for i in idx { engine.removeAthlete(id: engine.athletes[i].id) } }
            }
            .navigationTitle("Roster")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color.brand) } } }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("Full Name", text: $newName)
                        TextField("Jersey #", text: $newJersey).keyboardType(.numberPad)
                        TextField("Position", text: $newPosition)
                    }
                    .navigationTitle("Add Athlete")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Add") { if let n = Int(newJersey), !newName.isEmpty { engine.addAthlete(name: newName, jerseyNumber: n, position: newPosition); newName = ""; newJersey = ""; newPosition = ""; showAdd = false } }.disabled(newName.isEmpty) }
                    }
                }
            }
        }
    }
}

// MARK: - Sessions

struct SessionsListView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        NavigationStack {
            List {
                ForEach(engine.sessions.sorted(by: { $0.date > $1.date })) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.date, style: .date).font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                Text(s.isFresh ? "Fresh" : "Fatigued").font(.caption.weight(.medium))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(s.isFresh ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                                    .foregroundStyle(s.isFresh ? .green : .orange)
                                    .clipShape(Capsule())
                                Text("\(s.athleteIDs.count) athletes").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.quaternary)
                    }.padding(.vertical, 4)
                }
            }.navigationTitle("History")
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        @Bindable var engine = engine
        NavigationStack {
            Form {
                Section("Team") {
                    HStack { Text("Team Name"); Spacer(); Text(engine.teamName.isEmpty ? "My Team" : engine.teamName).foregroundStyle(.secondary) }
                    HStack { Text("Signed in as"); Spacer(); Text(engine.userName.isEmpty ? "User" : engine.userName).foregroundStyle(.secondary) }
                }
                Section("Risk Thresholds") {
                    HStack { Text("Caution (Yellow)"); Spacer(); TextField("", value: $engine.thresholds.yellowDelta, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 50) }
                    HStack { Text("High Risk (Red)"); Spacer(); TextField("", value: $engine.thresholds.redDelta, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 50) }
                }
                Section("About") {
                    HStack { Text("Version"); Spacer(); Text("1.0.0").foregroundStyle(.secondary) }
                    HStack { Text("Engine"); Spacer(); Text("LANDER CV v1").foregroundStyle(.secondary) }
                }
                Section {
                    Button("Reset Demo Data") { engine.seedDemoData() }
                    Button("Sign Out") { withAnimation { engine.isSignedIn = false } }.foregroundStyle(.red)
                }
            }.navigationTitle("Settings")
        }
    }
}
