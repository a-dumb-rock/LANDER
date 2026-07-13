import SwiftUI
import AuthenticationServices
import AVFoundation
import AVKit

// NOTE: Info.plist must include:
// NSCameraUsageDescription - "LANDER Buddy needs camera access to record landing videos for analysis."
// NSMicrophoneUsageDescription - "LANDER Buddy needs microphone access to record audio with landing videos."

// MARK: - Color Theme
extension Color {
    static let brand = Color(red: 0.75, green: 1.0, blue: 0.0)
    static let bgPrimary = Color(red: 0.04, green: 0.06, blue: 0.1)
    static let cardBg = Color(red: 0.08, green: 0.1, blue: 0.15)
    static let statusGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let statusYellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let statusRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let textSecondary = Color(white: 0.55)
}

// MARK: - Data Models
enum AthleteStatus: String, Codable { case good = "Good", caution = "Caution", atRisk = "At Risk", buildingBaseline = "Building Baseline" }
enum AthleteTrend: String, Codable { case improving = "Improving", stable = "Stable", worsening = "Worsening" }

struct DataPoint: Identifiable, Codable {
    let id: UUID
    let date: Date
    let value: Double
    let isFresh: Bool
    init(id: UUID = UUID(), date: Date, value: Double, isFresh: Bool) {
        self.id = id; self.date = date; self.value = value; self.isFresh = isFresh
    }
}

struct ModelMetrics {
    var valgusAngle: Double
    var kneeFlexionAngle: Double
    var trunkLean: Double
    var asymmetry: Double
    var lessScore: Int
}

struct CaptureItem: Identifiable {
    let id: UUID
    var name: String
    var videoAttached: Bool = false
    var videoURL: URL? = nil
    var thumbnail: UIImage? = nil
    var processing: Bool = false
    var done: Bool = false
    var resultMetrics: ModelMetrics?
}

struct Athlete: Identifiable, Codable {
    let id: UUID
    var name: String
    var jersey: Int
    var position: String
    var sessions: [DataPoint]
}


struct AthleteReadiness: Identifiable {
    let id: UUID
    var name: String
    let jersey: Int
    let position: String
    let fatigueDegradationPct: Double
    let status: AthleteStatus
    let trend: AthleteTrend
    let recommendation: String
    let valgusHistory: [DataPoint]
    let flexionHistory: [DataPoint]
    let deltaHistory: [DataPoint]
    let baselineValgus: Double
    let latestFatiguedValgus: Double
    let sessionCount: Int
    let allSessions: [DataPoint]
}

// MARK: - Persistence Helpers
struct PersistenceManager {
    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var dataFileURL: URL {
        documentsURL.appendingPathComponent("buddy_athletes.json")
    }
    static func saveAthletes(_ athletes: [Athlete]) {
        do {
            let data = try JSONEncoder().encode(athletes)
            try data.write(to: dataFileURL, options: .atomic)
        } catch { print("Save failed: \(error)") }
    }
    static func loadAthletes() -> [Athlete]? {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: dataFileURL)
            return try JSONDecoder().decode([Athlete].self, from: data)
        } catch { print("Load failed: \(error)"); return nil }
    }
}


// MARK: - Data Engine
@Observable
class DataEngine {
    var isSignedIn = false
    var athletes: [Athlete] = []
    var teamName = "FC Thunder"
    var userName = "Coach Davis"
    var cautionThreshold: Double = 10.0
    var atRiskThreshold: Double = 18.0

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    var storedTeamName: String {
        get { UserDefaults.standard.string(forKey: "teamName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "teamName") }
    }
    var storedCoachName: String {
        get { UserDefaults.standard.string(forKey: "coachName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "coachName") }
    }
    var storedSportType: String {
        get { UserDefaults.standard.string(forKey: "sportType") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "sportType") }
    }

    init() {
        if let saved = PersistenceManager.loadAthletes(), !saved.isEmpty {
            athletes = saved
        } else {
            loadDemoData()
        }
        if !storedTeamName.isEmpty { teamName = storedTeamName }
        if !storedCoachName.isEmpty { userName = storedCoachName }
    }

    func save() { PersistenceManager.saveAthletes(athletes) }

    func loadDemoData() {
        let cal = Calendar.current
        let now = Date()
        func weeksAgo(_ w: Int, day: Int) -> Date { cal.date(byAdding: .day, value: -(w * 7) + day, to: now)! }

        var maya: [DataPoint] = []
        for w in (0..<6).reversed() {
            maya.append(DataPoint(date: weeksAgo(w, day: 0), value: 6.0 + Double.random(in: -0.2...0.2), isFresh: true))
            maya.append(DataPoint(date: weeksAgo(w, day: 2), value: 6.3 + Double.random(in: -0.15...0.2), isFresh: false))
        }
        var carlos: [DataPoint] = []
        for w in (0..<6).reversed() {
            let p = Double(5 - w) / 5.0
            carlos.append(DataPoint(date: weeksAgo(w, day: 0), value: 7.0 + Double.random(in: -0.15...0.15), isFresh: true))
            carlos.append(DataPoint(date: weeksAgo(w, day: 2), value: 7.0 + (0.84 - p * 0.42) + Double.random(in: -0.1...0.1), isFresh: false))
        }
        var aisha: [DataPoint] = []
        for w in (0..<6).reversed() {
            let p = Double(5 - w) / 5.0
            aisha.append(DataPoint(date: weeksAgo(w, day: 0), value: 7.5 + Double.random(in: -0.15...0.15), isFresh: true))
            aisha.append(DataPoint(date: weeksAgo(w, day: 2), value: 7.5 + (0.6 + p * 0.45) + Double.random(in: -0.08...0.1), isFresh: false))
        }
        var jake: [DataPoint] = []
        for w in (0..<6).reversed() {
            let p = Double(5 - w) / 5.0
            jake.append(DataPoint(date: weeksAgo(w, day: 0), value: 8.0 + Double.random(in: -0.15...0.15), isFresh: true))
            jake.append(DataPoint(date: weeksAgo(w, day: 2), value: 8.0 + (0.96 + p * 0.96) + Double.random(in: -0.1...0.15), isFresh: false))
        }
        athletes = [
            Athlete(id: UUID(), name: "Maya Johnson", jersey: 7, position: "Forward", sessions: maya),
            Athlete(id: UUID(), name: "Carlos Rivera", jersey: 12, position: "Midfielder", sessions: carlos),
            Athlete(id: UUID(), name: "Aisha Patel", jersey: 3, position: "Defender", sessions: aisha),
            Athlete(id: UUID(), name: "Jake Thompson", jersey: 21, position: "Goalkeeper", sessions: jake)
        ]
        save()
    }


    func readiness(for athlete: Athlete) -> AthleteReadiness {
        let fresh = athlete.sessions.filter(\.isFresh)
        let fatigued = athlete.sessions.filter { !$0.isFresh }
        let baselineValgus = fresh.isEmpty ? 0 : fresh.map(\.value).reduce(0, +) / Double(fresh.count)
        let latestFatigued = fatigued.last?.value ?? baselineValgus
        let degradation: Double = (fresh.count < 2 || baselineValgus == 0) ? 0 : ((latestFatigued - baselineValgus) / baselineValgus) * 100.0

        let status: AthleteStatus
        if fresh.count < 4 { status = .buildingBaseline }
        else if degradation > atRiskThreshold { status = .atRisk }
        else if degradation > cautionThreshold { status = .caution }
        else { status = .good }

        let deltaHistory: [DataPoint] = zip(fresh, fatigued).map { f, t in
            DataPoint(date: t.date, value: baselineValgus > 0 ? ((t.value - f.value) / baselineValgus) * 100 : 0, isFresh: false)
        }

        let trend: AthleteTrend
        if deltaHistory.count >= 3 {
            let r = Array(deltaHistory.suffix(3))
            let diff = r.last!.value - r.first!.value
            if diff > 2 { trend = .worsening } else if diff < -2 { trend = .improving } else { trend = .stable }
        } else { trend = .stable }

        let recommendation: String
        switch (status, trend) {
        case (.atRisk, .worsening): recommendation = "Reduce load; landing degraded \(Int(degradation))% under fatigue, worsening 4 weeks. Consider rest day."
        case (.atRisk, _): recommendation = "High degradation at \(Int(degradation))%. Reduce jumping/cutting load."
        case (.caution, .worsening): recommendation = "Monitor — degradation trending up to \(Int(degradation))%. Ease plyometric volume."
        case (.caution, _): recommendation = "Moderate degradation at \(Int(degradation))%. Maintain load, monitor weekly."
        case (.good, .worsening): recommendation = "Currently good but trend worsening. Watch next 2 sessions."
        case (.good, .improving): recommendation = "Excellent — degradation reduced. Maintain current program."
        default: recommendation = "On track — maintain normal load."
        }

        let flexionHistory = athlete.sessions.map { DataPoint(date: $0.date, value: 55 + Double.random(in: -4...4), isFresh: $0.isFresh) }

        return AthleteReadiness(id: athlete.id, name: athlete.name, jersey: athlete.jersey, position: athlete.position,
            fatigueDegradationPct: max(0, degradation), status: status, trend: trend, recommendation: recommendation,
            valgusHistory: athlete.sessions, flexionHistory: flexionHistory, deltaHistory: deltaHistory,
            baselineValgus: baselineValgus, latestFatiguedValgus: latestFatigued,
            sessionCount: athlete.sessions.count, allSessions: athlete.sessions)
    }

    var allReadiness: [AthleteReadiness] { athletes.map { readiness(for: $0) }.sorted { $0.fatigueDegradationPct > $1.fatigueDegradationPct } }

    var teamScore: Int {
        let r = allReadiness; guard !r.isEmpty else { return 100 }
        let avg = r.map { max(0, 100 - $0.fatigueDegradationPct * 3) }.reduce(0, +) / Double(r.count)
        return Int(min(100, max(0, avg)))
    }

    var weekSessionCount: Int {
        athletes.flatMap(\.sessions).filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    var biggestMover: AthleteReadiness? { allReadiness.first }

    var teamDeltaTrend: [DataPoint] {
        guard let first = athletes.first else { return [] }
        let fatCount = first.sessions.filter { !$0.isFresh }.count
        return (0..<fatCount).map { i in
            let avg = athletes.compactMap { a -> Double? in
                let fr = a.sessions.filter(\.isFresh); let ft = a.sessions.filter { !$0.isFresh }
                guard i < ft.count, !fr.isEmpty else { return nil }
                let bl = fr.map(\.value).reduce(0, +) / Double(fr.count)
                return bl > 0 ? ((ft[i].value - bl) / bl) * 100 : 0
            }.reduce(0, +) / Double(athletes.count)
            let date = first.sessions.filter { !$0.isFresh }[i].date
            return DataPoint(date: date, value: avg, isFresh: false)
        }
    }

    func addAthlete(name: String, jersey: Int, position: String) {
        athletes.append(Athlete(id: UUID(), name: name, jersey: jersey, position: position, sessions: []))
        save()
    }
    func removeAthlete(_ id: UUID) { athletes.removeAll { $0.id == id }; save() }
    func resetDemo() { athletes.removeAll(); loadDemoData(); save() }
}


// MARK: - App Entry
@main
struct BuddyAppApp: App {
    @State private var engine = DataEngine()
    var body: some Scene {
        WindowGroup {
            Group {
                if engine.isSignedIn {
                    if engine.hasCompletedOnboarding {
                        MainTabView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        TeamSetupView()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: engine.isSignedIn)
            .animation(.easeInOut(duration: 0.4), value: engine.hasCompletedOnboarding)
            .environment(engine)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Onboarding
struct OnboardingView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "figure.run")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Color.brand)
                Text("LANDER").font(.system(size: 42, weight: .black)).foregroundStyle(.white)
                Text("BUDDY").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.brand)
                Text("Spot injury risk before it happens")
                    .font(.subheadline).foregroundStyle(Color.textSecondary)
                Spacer()
                SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in engine.isSignedIn = true }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50).cornerRadius(12).padding(.horizontal, 40)
                Button { engine.isSignedIn = true } label: {
                    HStack { Image(systemName: "g.circle.fill"); Text("Continue with Google") }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Color.cardBg).cornerRadius(12).foregroundStyle(.white)
                }.padding(.horizontal, 40)
                Button("Skip — use demo data") { engine.hasCompletedOnboarding = true; engine.isSignedIn = true }
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                Spacer().frame(height: 40)
            }
        }
    }
}


// MARK: - Team Setup (Post Sign-In Onboarding)
struct TeamSetupView: View {
    @Environment(DataEngine.self) private var engine
    @State private var teamNameInput = ""
    @State private var coachNameInput = ""
    @State private var sportType = "Soccer"
    private let sportOptions = ["Soccer", "Basketball", "Volleyball", "Track & Field", "Football", "Other"]

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 48)).foregroundStyle(Color.brand)
                Text("Set Up Your Team").font(.title2.bold()).foregroundStyle(.white)
                Text("Tell us about your team to get started")
                    .font(.subheadline).foregroundStyle(Color.textSecondary)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Team Name").font(.caption).foregroundStyle(Color.textSecondary)
                        TextField("e.g. FC Thunder", text: $teamNameInput)
                            .padding(12).background(Color.cardBg).cornerRadius(10)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sport").font(.caption).foregroundStyle(Color.textSecondary)
                        Picker("Sport", selection: $sportType) {
                            ForEach(sportOptions, id: \.self) { Text($0) }
                        }.pickerStyle(.menu).tint(Color.brand)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.cardBg).cornerRadius(10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coach Name").font(.caption).foregroundStyle(Color.textSecondary)
                        TextField("e.g. Coach Davis", text: $coachNameInput)
                            .padding(12).background(Color.cardBg).cornerRadius(10)
                            .foregroundStyle(.white)
                    }
                }.padding(.horizontal, 32)

                Spacer()
                Button {
                    engine.storedTeamName = teamNameInput.isEmpty ? "My Team" : teamNameInput
                    engine.storedCoachName = coachNameInput.isEmpty ? "Coach" : coachNameInput
                    engine.storedSportType = sportType
                    engine.teamName = engine.storedTeamName
                    engine.userName = engine.storedCoachName
                    engine.hasCompletedOnboarding = true
                } label: {
                    Text("Get Started").frame(maxWidth: .infinity).padding()
                        .background(Color.brand).foregroundStyle(.black)
                        .cornerRadius(12).bold()
                }.padding(.horizontal, 32)
                Spacer().frame(height: 40)
            }
        }
    }
}


// MARK: - Main Tab View
struct MainTabView: View {
    @State private var appeared = false
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Home", systemImage: "house.fill") }
            CaptureFlowView().tabItem { Label("Capture", systemImage: "camera.fill") }
            RosterView().tabItem { Label("Roster", systemImage: "person.3.fill") }
            HistoryView().tabItem { Label("History", systemImage: "clock.fill") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }.tint(Color.brand)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear { withAnimation(.easeInOut(duration: 0.3)) { appeared = true } }
    }
}

// MARK: - Sparkline (Inverted Y-axis: lower values = top, higher = bottom)
struct SparklineView: View {
    let points: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            if points.count > 1 {
                let mn = points.min()!; let mx = points.max()!
                let range = mx - mn == 0 ? 1 : mx - mn
                Path { path in
                    for (i, val) in points.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(points.count - 1)
                        // Inverted: higher values go DOWN (bad), lower values go UP (good)
                        let y = geo.size.height * CGFloat((val - mn) / range)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(color, lineWidth: 1.5)
            }
        }
    }
}


// MARK: - Line Chart (with axis labels, fresh/fatigued markers, baseline legend)
struct LineChartView: View {
    let data: [DataPoint]
    let baselineValue: Double?
    let lineColor: Color
    let title: String
    let unit: String
    var showFreshFatigued: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.textSecondary)
            HStack(spacing: 0) {
                // Y-axis labels
                let values = data.map(\.value)
                let allVals = baselineValue != nil ? values + [baselineValue!] : values
                let mn = allVals.min() ?? 0; let mx = allVals.max() ?? 1
                VStack {
                    Text(String(format: "%.1f", mx)).font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f", mn)).font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                }.frame(width: 28, height: 120)

                // Chart area
                GeometryReader { geo in
                    let range = mx - mn == 0 ? 1 : mx - mn
                    let h = geo.size.height; let w = geo.size.width

                    ZStack {
                        // Fill gradient
                        Path { path in
                            for (i, val) in values.enumerated() {
                                let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                                let y = h * (1 - CGFloat((val - mn) / range))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            path.addLine(to: CGPoint(x: w, y: h))
                            path.addLine(to: CGPoint(x: 0, y: h))
                            path.closeSubpath()
                        }.fill(LinearGradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0.0)], startPoint: .top, endPoint: .bottom))

                        // Line
                        Path { path in
                            for (i, val) in values.enumerated() {
                                let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                                let y = h * (1 - CGFloat((val - mn) / range))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(lineColor, lineWidth: 2.5)

                        // Fresh/Fatigued dot markers
                        if showFreshFatigued {
                            ForEach(Array(data.enumerated()), id: \.offset) { i, dp in
                                let x = w * CGFloat(i) / CGFloat(max(data.count - 1, 1))
                                let y = h * (1 - CGFloat((dp.value - mn) / range))
                                Circle()
                                    .fill(dp.isFresh ? Color.statusGreen : Color.statusYellow)
                                    .frame(width: dp.isFresh ? 5 : 7, height: dp.isFresh ? 5 : 7)
                                    .overlay(dp.isFresh ? Circle().stroke(Color.statusGreen, lineWidth: 1.5).frame(width: 7, height: 7) : nil)
                                    .position(x: x, y: y)
                            }
                        }

                        // Baseline dashed
                        if let bl = baselineValue {
                            let by = h * (1 - CGFloat((bl - mn) / range))
                            Path { path in path.move(to: CGPoint(x: 0, y: by)); path.addLine(to: CGPoint(x: w, y: by)) }
                                .stroke(Color.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                    }
                }.frame(height: 120)
            }
            // X-axis date labels
            if let first = data.first, let last = data.last {
                HStack {
                    Spacer().frame(width: 28)
                    Text(first.date, format: .dateTime.month(.abbreviated).day()).font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(last.date, format: .dateTime.month(.abbreviated).day()).font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                }
            }
            // Baseline legend
            if baselineValue != nil {
                HStack(spacing: 4) {
                    Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 16, y: 0)) }
                        .stroke(Color.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 16, height: 1)
                    Text("Baseline").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                    if showFreshFatigued {
                        Spacer().frame(width: 8)
                        Circle().fill(Color.statusGreen).frame(width: 5, height: 5)
                        Text("Fresh").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                        Circle().fill(Color.statusYellow).frame(width: 6, height: 6)
                        Text("Fatigued").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                    }
                }.padding(.leading, 28)
            }
            HStack { Spacer().frame(width: 28); Text(unit).font(.caption2).foregroundStyle(Color.textSecondary); Spacer() }
        }
        .padding().background(Color.cardBg).cornerRadius(12)
    }
}


// MARK: - Status & Trend Helpers
struct StatusBadge: View {
    let status: AthleteStatus
    var color: Color {
        switch status {
        case .good: return .statusGreen
        case .caution: return .statusYellow
        case .atRisk: return .statusRed
        case .buildingBaseline: return .textSecondary
        }
    }
    var body: some View {
        Text(status.rawValue).font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.2)).foregroundStyle(color)
            .cornerRadius(6)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: status.rawValue)
    }
}

struct TrendBadge: View {
    let trend: AthleteTrend
    var icon: String {
        switch trend {
        case .worsening: return "arrow.up.right"
        case .improving: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
    var color: Color {
        switch trend {
        case .worsening: return .statusRed
        case .improving: return .statusGreen
        case .stable: return .textSecondary
        }
    }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(trend.rawValue).font(.system(size: 10).bold())
                .lineLimit(1).minimumScaleFactor(0.8)
        }.foregroundStyle(color)
    }
}

struct JerseyCircle: View {
    let number: Int; let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.brand.opacity(0.15)).frame(width: size, height: size)
            Text("#\(number)").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(Color.brand)
        }
    }
}


// MARK: - Dashboard
struct DashboardView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Top metric cards
                    HStack(spacing: 12) {
                        MetricCard(title: "Team Score", value: "\(engine.teamScore)", subtitle: "/ 100", color: .brand)
                        MetricCard(title: "This Week", value: "\(engine.weekSessionCount)", subtitle: "sessions", color: Color.statusGreen)
                        if let mover = engine.biggestMover {
                            MetricCard(title: "Biggest Mover", value: "\(Int(mover.fatigueDegradationPct))%", subtitle: mover.name, color: Color.statusRed)
                        }
                    }.padding(.horizontal)

                    // Alert banner
                    let atRisk = engine.allReadiness.filter { $0.status == .atRisk }
                    if !atRisk.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusRed)
                            Text("\(atRisk.count) athlete\(atRisk.count > 1 ? "s" : "") at risk — tap for details")
                                .font(.caption).foregroundStyle(.white)
                            Spacer()
                        }.padding(12).background(Color.statusRed.opacity(0.15)).cornerRadius(10).padding(.horizontal)
                    }

                    // Team trend chart with "6 wks" label
                    if engine.teamDeltaTrend.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Team Avg Fatigue Delta").font(.caption).foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("6 wks").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                            }
                            SparklineView(points: engine.teamDeltaTrend.map(\.value), color: .brand)
                                .frame(height: 50)
                        }.padding().background(Color.cardBg).cornerRadius(12).padding(.horizontal)
                    }

                    // Athlete list sorted worst-first
                    VStack(spacing: 8) {
                        ForEach(engine.allReadiness) { r in
                            NavigationLink(value: r.id) {
                                AthleteRow(readiness: r)
                            }.buttonStyle(CardPressStyle())
                        }
                    }.padding(.horizontal)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: engine.allReadiness.map(\.fatigueDegradationPct))
                }
                .padding(.vertical)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Dashboard")
            .navigationDestination(for: UUID.self) { id in AthleteDetailView(athleteID: id) }
        }
    }
}

struct MetricCard: View {
    let title: String; let value: String; let subtitle: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(Color.textSecondary).lineLimit(1)
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(Color.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(12)
        .background(Color.cardBg).cornerRadius(12)
    }
}

struct AthleteRow: View {
    let readiness: AthleteReadiness
    var body: some View {
        HStack(spacing: 12) {
            JerseyCircle(number: readiness.jersey, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(readiness.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                Text(readiness.position).font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            // Sparkline (inverted y: upward = bad)
            SparklineView(points: readiness.deltaHistory.suffix(5).map(\.value),
                color: readiness.trend == .worsening ? Color.statusRed : readiness.trend == .improving ? Color.statusGreen : Color.textSecondary)
                .frame(width: 40, height: 20)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(readiness.fatigueDegradationPct))%").font(.subheadline.bold())
                    .foregroundStyle(readiness.status == .atRisk ? Color.statusRed : readiness.status == .caution ? Color.statusYellow : Color.statusGreen)
                HStack(spacing: 4) { StatusBadge(status: readiness.status); TrendBadge(trend: readiness.trend) }
            }
        }
        .padding(12).background(Color.cardBg).cornerRadius(12)
    }
}

// MARK: - Card Press Style
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}


// MARK: - Athlete Detail
struct AthleteDetailView: View {
    @Environment(DataEngine.self) private var engine
    let athleteID: UUID
    private var r: AthleteReadiness? { engine.allReadiness.first { $0.id == athleteID } }
    @State private var chartsVisible = false

    var body: some View {
        ScrollView {
            if let r = r {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        JerseyCircle(number: r.jersey, size: 64)
                        Text(r.name).font(.title2.bold()).foregroundStyle(.white)
                        Text(r.position).font(.subheadline).foregroundStyle(Color.textSecondary)
                        HStack(spacing: 12) { StatusBadge(status: r.status); TrendBadge(trend: r.trend) }
                    }.padding(.top)

                    // Recommendation
                    HStack {
                        Image(systemName: "lightbulb.fill").foregroundStyle(Color.brand)
                        Text(r.recommendation).font(.callout).foregroundStyle(.white)
                    }.padding().background(Color.cardBg).cornerRadius(12).padding(.horizontal)

                    // Valgus chart with fresh/fatigued markers
                    LineChartView(data: r.valgusHistory, baselineValue: r.baselineValgus, lineColor: .brand, title: "Knee Valgus", unit: "degrees", showFreshFatigued: true)
                        .padding(.horizontal)
                        .opacity(chartsVisible ? 1.0 : 0.0)
                        .offset(y: chartsVisible ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: chartsVisible)
                    LineChartView(data: r.flexionHistory, baselineValue: 55.0, lineColor: Color.statusGreen, title: "Knee Flexion", unit: "degrees")
                        .padding(.horizontal)
                        .opacity(chartsVisible ? 1.0 : 0.0)
                        .offset(y: chartsVisible ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: chartsVisible)
                    LineChartView(data: r.deltaHistory, baselineValue: 0, lineColor: Color.statusRed, title: "Fatigue Delta", unit: "% degradation")
                        .padding(.horizontal)
                        .opacity(chartsVisible ? 1.0 : 0.0)
                        .offset(y: chartsVisible ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: chartsVisible)

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCell(label: "Baseline Valgus", value: String(format: "%.1f°", r.baselineValgus))
                        StatCell(label: "Latest Fatigued", value: String(format: "%.1f°", r.latestFatiguedValgus))
                        StatCell(label: "Degradation", value: "\(Int(r.fatigueDegradationPct))%")
                        StatCell(label: "Sessions", value: "\(r.sessionCount)")
                    }.padding(.horizontal)

                    // Session history
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session History").font(.headline).foregroundStyle(.white)
                        ForEach(r.allSessions.reversed()) { s in
                            HStack {
                                Text(s.date, style: .date).font(.caption).foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text(s.isFresh ? "Fresh" : "Fatigued").font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(s.isFresh ? Color.statusGreen.opacity(0.2) : Color.statusYellow.opacity(0.2))
                                    .foregroundStyle(s.isFresh ? Color.statusGreen : Color.statusYellow)
                                    .cornerRadius(4)
                                Text(String(format: "%.1f°", s.value)).font(.caption.bold()).foregroundStyle(.white)
                            }
                        }
                    }.padding()
                }
                .transition(.opacity)
            } else {
                Text("Athlete not found").foregroundStyle(Color.textSecondary)
            }
        }
        .background(Color.bgPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { chartsVisible = true }
    }
}

struct StatCell: View {
    let label: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(value).font(.title3.bold()).foregroundStyle(.white)
        }.frame(maxWidth: .infinity).padding(12).background(Color.cardBg).cornerRadius(10)
    }
}


// MARK: - Camera Integration (AVFoundation)
struct CameraView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let url = info[.mediaURL] as? URL
            picker.dismiss(animated: true) { self.onComplete(url) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onComplete(nil) }
        }
    }
}

func generateThumbnail(from url: URL) -> UIImage? {
    let asset = AVAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    do {
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: cgImage)
    } catch { return nil }
}


// MARK: - Capture Flow
struct CaptureFlowView: View {
    @Environment(DataEngine.self) private var engine
    @State private var step = 1
    @State private var selectedDate = Date()
    @State private var isFresh = true
    @State private var selectedAthleteIDs: Set<UUID> = []
    @State private var captureItems: [CaptureItem] = []
    @State private var consentGiven = false
    @State private var analyzing = false
    @State private var showCameraFor: CameraSheetItem? = nil
    @State private var cameraSourceType: UIImagePickerController.SourceType = .camera
    @State private var showVideoActionSheet = false
    @State private var actionSheetItemID: UUID? = nil
    @State private var cameraPermissionDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Progress bar
                    HStack(spacing: 4) {
                        ForEach(1...4, id: \.self) { s in
                            Capsule().fill(s <= step ? Color.brand : Color.cardBg).frame(height: 4)
                        }
                    }.padding()

                    ScrollView {
                        VStack(spacing: 20) {
                            if step == 1 { captureStep1.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                            else if step == 2 { captureStep2.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                            else if step == 3 { captureStep3.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                            else { captureStep4.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))) }
                        }.padding()
                        .animation(.easeInOut(duration: 0.3), value: step)
                    }
                }
            }
            .navigationTitle("Capture")
            .fullScreenCover(item: $showCameraFor) { sheetItem in
                CameraView(sourceType: cameraSourceType) { url in
                    if let url = url, let idx = captureItems.firstIndex(where: { $0.id == sheetItem.id }) {
                        captureItems[idx].videoURL = url
                        captureItems[idx].videoAttached = true
                        captureItems[idx].thumbnail = generateThumbnail(from: url)
                    }
                    showCameraFor = nil
                }.ignoresSafeArea()
            }
            .alert("Camera Access Denied", isPresented: $cameraPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable camera access in Settings to record landing videos.")
            }
        }
    }

    private func checkCameraAndRecord(for id: UUID) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraSourceType = .camera
            showCameraFor = CameraSheetItem(id: id)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { cameraSourceType = .camera; showCameraFor = CameraSheetItem(id: id) }
                    else { cameraPermissionDenied = true }
                }
            }
        default:
            cameraPermissionDenied = true
        }
    }


    private var captureStep1: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Details").font(.title3.bold()).foregroundStyle(.white)
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date).tint(.brand)
            Picker("Type", selection: $isFresh) {
                Text("Fresh").tag(true)
                Text("Fatigued").tag(false)
            }.pickerStyle(.segmented).tint(.brand)

            Text("Select Athletes").font(.headline).foregroundStyle(.white).padding(.top)
            ForEach(engine.athletes) { a in
                Button {
                    if selectedAthleteIDs.contains(a.id) { selectedAthleteIDs.remove(a.id) }
                    else { selectedAthleteIDs.insert(a.id) }
                } label: {
                    HStack {
                        JerseyCircle(number: a.jersey, size: 36)
                        Text(a.name).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        if selectedAthleteIDs.contains(a.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
                        } else {
                            Image(systemName: "circle").foregroundStyle(Color.textSecondary)
                        }
                    }.padding(10).background(Color.cardBg).cornerRadius(10)
                }
            }

            Button {
                captureItems = selectedAthleteIDs.compactMap { id in
                    guard let a = engine.athletes.first(where: { $0.id == id }) else { return nil }
                    return CaptureItem(id: a.id, name: a.name)
                }
                withAnimation(.easeInOut(duration: 0.3)) { step = 2 }
            } label: {
                Text("Next →").frame(maxWidth: .infinity).padding()
                    .background(selectedAthleteIDs.isEmpty ? Color.cardBg : Color.brand)
                    .foregroundStyle(selectedAthleteIDs.isEmpty ? Color.textSecondary : .black)
                    .cornerRadius(12).bold()
            }.disabled(selectedAthleteIDs.isEmpty)
        }
    }


    private var captureStep2: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upload Videos").font(.title3.bold()).foregroundStyle(.white)
            Text("Record or upload a landing video for each athlete.").font(.caption).foregroundStyle(Color.textSecondary)

            ForEach($captureItems) { $item in
                HStack {
                    // Thumbnail if available
                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable().scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(item.name).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    if item.videoAttached {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.statusGreen).font(.title3)
                    } else {
                        Button {
                            actionSheetItemID = item.id
                            showVideoActionSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video.badge.plus")
                                Text("Add Video")
                            }.font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.brand.opacity(0.2)).foregroundStyle(Color.brand).cornerRadius(8)
                        }
                    }
                }.padding(12).background(Color.cardBg).cornerRadius(10)
            }
            .confirmationDialog("Add Video", isPresented: $showVideoActionSheet, titleVisibility: .visible) {
                Button("Record with Camera") {
                    if let id = actionSheetItemID { checkCameraAndRecord(for: id) }
                }
                Button("Upload from Library") {
                    if let id = actionSheetItemID {
                        cameraSourceType = .photoLibrary
                        showCameraFor = CameraSheetItem(id: id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            // Consent
            Toggle(isOn: $consentGiven) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consent Confirmed").font(.subheadline.bold()).foregroundStyle(.white)
                    Text("I confirm consent has been obtained from all athletes in this recording.")
                        .font(.caption2).foregroundStyle(Color.textSecondary)
                }
            }.tint(Color.brand).padding(.top)

            let allAttached = captureItems.allSatisfy(\.videoAttached)
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { step = 3 }; startAnalysis()
            } label: {
                Text("Analyze Landing →").frame(maxWidth: .infinity).padding()
                    .background(allAttached && consentGiven ? Color.brand : Color.cardBg)
                    .foregroundStyle(allAttached && consentGiven ? .black : Color.textSecondary)
                    .cornerRadius(12).bold()
            }.disabled(!allAttached || !consentGiven)

            Button("← Back") { withAnimation(.easeInOut(duration: 0.3)) { step = 1 } }.font(.caption).foregroundStyle(Color.textSecondary)
        }
    }


    private var captureStep3: some View {
        VStack(spacing: 20) {
            Text("Analyzing...").font(.title3.bold()).foregroundStyle(.white)
            ForEach(captureItems) { item in
                HStack {
                    Text(item.name).foregroundStyle(.white)
                    Spacer()
                    if item.done {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusGreen)
                            .scaleEffect(item.done ? 1.0 : 0.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.done)
                    } else if item.processing {
                        ProgressView().tint(Color.brand)
                    } else {
                        Circle().fill(Color.cardBg).frame(width: 20, height: 20)
                    }
                }.padding(12).background(Color.cardBg).cornerRadius(10)
            }
            if captureItems.allSatisfy(\.done) {
                Button { withAnimation(.easeInOut(duration: 0.3)) { step = 4 } } label: {
                    Text("View Results →").frame(maxWidth: .infinity).padding()
                        .background(Color.brand).foregroundStyle(.black).cornerRadius(12).bold()
                }
            }
        }
    }

    private var captureStep4: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results").font(.title3.bold()).foregroundStyle(.white)
            Text(isFresh ? "Fresh session recorded" : "Fatigued session — showing delta vs baseline")
                .font(.caption).foregroundStyle(Color.textSecondary)

            ForEach(captureItems) { item in
                if let m = item.resultMetrics {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.subheadline.bold()).foregroundStyle(.white)
                        HStack(spacing: 16) {
                            VStack { Text("Valgus").font(.caption2).foregroundStyle(Color.textSecondary); Text(String(format: "%.1f°", m.valgusAngle)).foregroundStyle(.white).bold() }
                            VStack { Text("Flexion").font(.caption2).foregroundStyle(Color.textSecondary); Text(String(format: "%.1f°", m.kneeFlexionAngle)).foregroundStyle(.white).bold() }
                            VStack { Text("Asym").font(.caption2).foregroundStyle(Color.textSecondary); Text(String(format: "%.0f%%", m.asymmetry)).foregroundStyle(.white).bold() }
                            if !isFresh, let a = engine.athletes.first(where: { $0.id == item.id }) {
                                let bl = a.sessions.filter(\.isFresh).map(\.value).reduce(0, +) / max(1, Double(a.sessions.filter(\.isFresh).count))
                                let delta = bl > 0 ? ((m.valgusAngle - bl) / bl) * 100 : 0
                                VStack { Text("Delta").font(.caption2).foregroundStyle(Color.textSecondary); Text("+\(Int(delta))%").foregroundStyle(delta > 18 ? Color.statusRed : delta > 10 ? Color.statusYellow : Color.statusGreen).bold() }
                            }
                        }
                    }.padding().background(Color.cardBg).cornerRadius(10)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { step = 1 }; captureItems = []; selectedAthleteIDs = []; consentGiven = false
            } label: {
                Text("Done").frame(maxWidth: .infinity).padding()
                    .background(Color.brand).foregroundStyle(.black).cornerRadius(12).bold()
            }
        }
    }

    private func startAnalysis() {
        for i in captureItems.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8) {
                captureItems[i].processing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8 + 1.2) {
                captureItems[i].processing = false
                captureItems[i].done = true
                let valgus = Double.random(in: 5.5...10.5)
                captureItems[i].resultMetrics = ModelMetrics(
                    valgusAngle: valgus, kneeFlexionAngle: Double.random(in: 48...62),
                    trunkLean: Double.random(in: 3...12), asymmetry: Double.random(in: 2...15), lessScore: Int.random(in: 55...95))
                if let idx = engine.athletes.firstIndex(where: { $0.id == captureItems[i].id }) {
                    engine.athletes[idx].sessions.append(DataPoint(date: selectedDate, value: valgus, isFresh: isFresh))
                    engine.save()
                }
            }
        }
    }
}


// MARK: - Camera Sheet Item (replaces @retroactive Identifiable on UUID)
struct CameraSheetItem: Identifiable {
    let id: UUID
}

// MARK: - Roster (with status badges)
struct RosterView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newJersey = ""
    @State private var newPosition = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if engine.athletes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3").font(.largeTitle).foregroundStyle(Color.textSecondary)
                        Text("No athletes yet").foregroundStyle(Color.textSecondary)
                        Text("Tap + to add your first athlete").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                } else {
                    List {
                        ForEach(engine.athletes) { a in
                            let r = engine.readiness(for: a)
                            NavigationLink(value: a.id) {
                                HStack(spacing: 12) {
                                    JerseyCircle(number: a.jersey, size: 40)
                                    VStack(alignment: .leading) {
                                        Text(a.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                        Text(a.position).font(.caption).foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                    StatusBadge(status: r.status)
                                }
                            }.listRowBackground(Color.cardBg)
                        }
                        .onDelete { idxs in
                            for i in idxs { engine.removeAthlete(engine.athletes[i].id) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Roster")
            .navigationDestination(for: UUID.self) { id in AthleteDetailView(athleteID: id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.brand) }
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $newName)
                        TextField("Jersey #", text: $newJersey).keyboardType(.numberPad)
                        TextField("Position", text: $newPosition)
                    }
                    .navigationTitle("Add Athlete")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                engine.addAthlete(name: newName, jersey: Int(newJersey) ?? 0, position: newPosition)
                                newName = ""; newJersey = ""; newPosition = ""; showingAdd = false
                            }.disabled(newName.isEmpty)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - History
struct HistoryView: View {
    @Environment(DataEngine.self) private var engine
    @State private var selectedSessionSheet: SessionSheetID? = nil

    private var groupedSessions: [(date: Date, isFresh: Bool, count: Int)] {
        var result: [(Date, Bool, Int)] = []
        for athlete in engine.athletes {
            for s in athlete.sessions {
                let key = "\(s.date.timeIntervalSince1970)-\(s.isFresh)"
                if !result.contains(where: { "\($0.0.timeIntervalSince1970)-\($0.1)" == key }) {
                    let count = engine.athletes.filter { a in a.sessions.contains { $0.date == s.date && $0.isFresh == s.isFresh } }.count
                    result.append((s.date, s.isFresh, count))
                }
            }
        }
        return result.sorted { $0.0 > $1.0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if groupedSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock").font(.largeTitle).foregroundStyle(Color.textSecondary)
                        Text("No sessions yet").foregroundStyle(Color.textSecondary)
                    }
                } else {
                    List {
                        ForEach(groupedSessions, id: \.date) { session in
                            Button {
                                selectedSessionSheet = SessionSheetID(date: session.date, isFresh: session.isFresh)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.date, style: .date).font(.subheadline.bold()).foregroundStyle(.white)
                                        Text("\(session.count) athletes").font(.caption).foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                    Text(session.isFresh ? "Fresh" : "Fatigued").font(.caption2.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(session.isFresh ? Color.statusGreen.opacity(0.2) : Color.statusYellow.opacity(0.2))
                                        .foregroundStyle(session.isFresh ? Color.statusGreen : Color.statusYellow)
                                        .cornerRadius(5)
                                }
                            }.listRowBackground(Color.cardBg)
                        }
                    }
                    .scrollContentBackground(.hidden).listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedSessionSheet) { item in
                SessionDetailSheet(date: item.date, isFresh: item.isFresh)
            }
        }
    }
}

struct SessionSheetID: Identifiable {
    let date: Date; let isFresh: Bool
    var id: String { "\(date.timeIntervalSince1970)-\(isFresh)" }
}


// MARK: - Session Detail (with color-coded valgus values)
struct SessionDetailSheet: View {
    @Environment(DataEngine.self) private var engine
    let date: Date; let isFresh: Bool

    private func valgusColor(for athlete: Athlete, value: Double) -> Color {
        let fresh = athlete.sessions.filter(\.isFresh)
        guard !fresh.isEmpty else { return .white }
        let baseline = fresh.map(\.value).reduce(0, +) / Double(fresh.count)
        guard baseline > 0 else { return .white }
        let deltaPct = ((value - baseline) / baseline) * 100
        if deltaPct > engine.atRiskThreshold { return Color.statusRed }
        else if deltaPct > engine.cautionThreshold { return Color.statusYellow }
        else { return Color.statusGreen }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isFresh ? "Fresh Session" : "Fatigued Session").font(.headline).foregroundStyle(.white)
                        Text(date, style: .date).font(.subheadline).foregroundStyle(Color.textSecondary)
                        Divider().background(Color.cardBg)
                        ForEach(engine.athletes) { a in
                            if let s = a.sessions.first(where: { $0.date == date && $0.isFresh == isFresh }) {
                                HStack {
                                    JerseyCircle(number: a.jersey, size: 32)
                                    Text(a.name).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.1f°", s.value)).font(.subheadline.bold())
                                        .foregroundStyle(isFresh ? .white : valgusColor(for: a, value: s.value))
                                }.padding(10).background(Color.cardBg).cornerRadius(8)
                            }
                        }
                    }.padding()
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Settings
struct SettingsView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                List {
                    Section("Team") {
                        HStack {
                            Text("Team Name").foregroundStyle(.white)
                            Spacer()
                            TextField("", text: Binding(get: { engine.teamName }, set: { engine.teamName = $0; engine.storedTeamName = $0 }))
                                .multilineTextAlignment(.trailing).foregroundStyle(Color.brand)
                        }.listRowBackground(Color.cardBg)
                        HStack {
                            Text("Coach").foregroundStyle(.white)
                            Spacer()
                            TextField("", text: Binding(get: { engine.userName }, set: { engine.userName = $0; engine.storedCoachName = $0 }))
                                .multilineTextAlignment(.trailing).foregroundStyle(Color.brand)
                        }.listRowBackground(Color.cardBg)
                        HStack {
                            Text("Sport").foregroundStyle(.white)
                            Spacer()
                            Text(engine.storedSportType.isEmpty ? "Not set" : engine.storedSportType)
                                .foregroundStyle(Color.textSecondary)
                        }.listRowBackground(Color.cardBg)
                    }

                    Section("Risk Thresholds (Fatigue Degradation %)") {
                        HStack {
                            Text("Caution at").foregroundStyle(.white)
                            Spacer()
                            TextField("", value: Binding(get: { engine.cautionThreshold }, set: { engine.cautionThreshold = $0 }), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60).foregroundStyle(Color.statusYellow)
                            Text("%").foregroundStyle(Color.textSecondary)
                        }.listRowBackground(Color.cardBg)
                        HStack {
                            Text("At Risk at").foregroundStyle(.white)
                            Spacer()
                            TextField("", value: Binding(get: { engine.atRiskThreshold }, set: { engine.atRiskThreshold = $0 }), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60).foregroundStyle(Color.statusRed)
                            Text("%").foregroundStyle(Color.textSecondary)
                        }.listRowBackground(Color.cardBg)
                    }

                    Section("About") {
                        HStack { Text("Version").foregroundStyle(.white); Spacer(); Text("2.1.0").foregroundStyle(Color.textSecondary) }.listRowBackground(Color.cardBg)
                        HStack { Text("Build").foregroundStyle(.white); Spacer(); Text("2025.07").foregroundStyle(Color.textSecondary) }.listRowBackground(Color.cardBg)
                    }

                    Section {
                        Button("Reset Demo Data") { showResetConfirm = true }
                            .foregroundStyle(Color.statusYellow).listRowBackground(Color.cardBg)
                        Button("Sign Out") { engine.isSignedIn = false; engine.hasCompletedOnboarding = false }
                            .foregroundStyle(Color.statusRed).listRowBackground(Color.cardBg)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .alert("Reset Demo Data?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { engine.resetDemo() }
            } message: { Text("This will replace all data with fresh demo athletes.") }
        }
    }
}
