import SwiftUI
import AuthenticationServices

// MARK: - Theme Colors (matches landeracl.com)

extension Color {
    static let brand = Color(red: 0.75, green: 1.0, blue: 0.0)          // Lime green #BFFF00
    static let brandDim = Color(red: 0.55, green: 0.8, blue: 0.0)       // Darker lime
    static let bgPrimary = Color(red: 0.04, green: 0.06, blue: 0.1)     // Deep navy #0A0F1A
    static let bgCard = Color(red: 0.08, green: 0.1, blue: 0.15)        // Card bg
    static let bgCardLight = Color(red: 0.12, green: 0.14, blue: 0.2)   // Lighter card
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.55)
    static let statusGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let statusYellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let statusRed = Color(red: 1.0, green: 0.3, blue: 0.3)
}

// MARK: - Models

enum ReadinessStatus: String, CaseIterable {
    case green = "Good"
    case yellow = "Caution"
    case red = "At Risk"
    var color: Color {
        switch self {
        case .green: return .statusGreen
        case .yellow: return .statusYellow
        case .red: return .statusRed
        }
    }
    var bgColor: Color { color.opacity(0.15) }
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
        case .improving: return .statusGreen
        case .stable: return .textSecondary
        case .declining: return .statusRed
        }
    }
}

struct Thresholds { var yellowDelta: Double = 8.0; var redDelta: Double = 15.0 }

struct Athlete: Identifiable {
    let id: UUID; var name: String; var jerseyNumber: Int; var position: String
}

struct CaptureSession: Identifiable {
    let id: UUID; let date: Date; let isFresh: Bool; let athleteIDs: [UUID]; var metrics: [UUID: ModelMetrics]
}

struct ModelMetrics: Identifiable {
    let id = UUID()
    let kneeFlexionAngle: Double; let valgusAngle: Double; let landingForce: Double; let stabilizationTime: Double; let symmetryIndex: Double
    var compositeScore: Double {
        let flex = min(max((kneeFlexionAngle - 30) / 40, 0), 1) * 100
        let valg = min(max((15 - valgusAngle) / 15, 0), 1) * 100
        let force = min(max((5 - landingForce) / 3, 0), 1) * 100
        let stab = min(max((1.5 - stabilizationTime) / 1.0, 0), 1) * 100
        return (flex + valg + force + stab + symmetryIndex) / 5.0
    }
}

struct AthleteReadiness: Identifiable {
    let id: UUID; let athlete: Athlete; let currentScore: Double; let baselineScore: Double
    let delta: Double; let status: ReadinessStatus; let trend: TrendDirection; let history: [Double]
}



// MARK: - Data Engine

@Observable
class DataEngine {
    var athletes: [Athlete] = []
    var sessions: [CaptureSession] = []
    var thresholds = Thresholds()
    var isSignedIn = false
    var userName = ""
    var teamName = ""

    init() { seedDemoData() }

    func seedDemoData() {
        athletes = [
            Athlete(id: UUID(), name: "Maya Johnson", jerseyNumber: 7, position: "Forward"),
            Athlete(id: UUID(), name: "Carlos Rivera", jerseyNumber: 12, position: "Midfielder"),
            Athlete(id: UUID(), name: "Aisha Patel", jerseyNumber: 3, position: "Defender"),
            Athlete(id: UUID(), name: "Jake Thompson", jerseyNumber: 21, position: "Goalkeeper")
        ]
        let today = Date(); var allSessions: [CaptureSession] = []
        for weekOffset in (0..<4).reversed() {
            for dayOffset in [0, 3] {
                let date = Calendar.current.date(byAdding: .day, value: -(weekOffset * 7 + dayOffset), to: today)!
                let isFresh = dayOffset == 0
                var metrics: [UUID: ModelMetrics] = [:]
                for (i, a) in athletes.enumerated() { metrics[a.id] = genMetrics(fatigue: isFresh ? 0 : Double(weekOffset) * 0.5 + Double(i) * 0.3, idx: i) }
                allSessions.append(CaptureSession(id: UUID(), date: date, isFresh: isFresh, athleteIDs: athletes.map { $0.id }, metrics: metrics))
            }
        }
        sessions = allSessions.sorted { $0.date < $1.date }
    }

    private func genMetrics(fatigue: Double, idx: Int) -> ModelMetrics {
        ModelMetrics(kneeFlexionAngle: 45 + Double(idx)*3 - fatigue*2 + .random(in: -2...2), valgusAngle: 5 + fatigue*1.5 + .random(in: -1...1), landingForce: 2.5 + fatigue*0.3 + .random(in: -0.2...0.2), stabilizationTime: 0.6 + fatigue*0.1 + .random(in: -0.05...0.05), symmetryIndex: 92 - fatigue*2 + .random(in: -1...1))
    }

    func computeReadiness() -> [AthleteReadiness] {
        athletes.map { athlete in
            let sess = sessions.filter { $0.athleteIDs.contains(athlete.id) }
            let freshScores = sess.filter { $0.isFresh }.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let fatiguedScores = sess.filter { !$0.isFresh }.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let baseline = freshScores.isEmpty ? 80 : freshScores.reduce(0,+) / Double(freshScores.count)
            let current = fatiguedScores.last ?? baseline
            let delta = baseline - current
            let status: ReadinessStatus = delta >= thresholds.redDelta ? .red : delta >= thresholds.yellowDelta ? .yellow : .green
            let all = sess.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let trend: TrendDirection = all.count >= 3 ? { let d = all.suffix(3).last! - all.suffix(3).first!; return d > 2 ? .improving : d < -2 ? .declining : .stable }() : .stable
            return AthleteReadiness(id: athlete.id, athlete: athlete, currentScore: current, baselineScore: baseline, delta: delta, status: status, trend: trend, history: all)
        }.sorted { ord($0.status) < ord($1.status) }
    }

    private func ord(_ s: ReadinessStatus) -> Int { s == .red ? 0 : s == .yellow ? 1 : 2 }
    func addAthlete(name: String, jerseyNumber: Int, position: String) { athletes.append(Athlete(id: UUID(), name: name, jerseyNumber: jerseyNumber, position: position)) }
    func removeAthlete(id: UUID) { athletes.removeAll { $0.id == id } }
    func runCapture(date: Date, isFresh: Bool, athleteIDs: [UUID]) {
        var m: [UUID: ModelMetrics] = [:]
        for (i, id) in athleteIDs.enumerated() { m[id] = genMetrics(fatigue: isFresh ? 0 : .random(in: 1...4), idx: i) }
        sessions.append(CaptureSession(id: UUID(), date: date, isFresh: isFresh, athleteIDs: athleteIDs, metrics: m))
        sessions.sort { $0.date < $1.date }
    }
}



// MARK: - App Entry

@main
struct BuddyAppApp: App {
    @State private var engine = DataEngine()
    var body: some Scene {
        WindowGroup {
            Group {
                if engine.isSignedIn { MainTabView().environment(engine) }
                else { OnboardingView().environment(engine) }
            }.preferredColorScheme(.dark)
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Environment(DataEngine.self) private var engine
    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                // Logo
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.brand.opacity(0.1)).frame(width: 100, height: 100)
                        Image(systemName: "figure.run").font(.system(size: 42, weight: .medium)).foregroundStyle(Color.brand)
                    }
                    HStack(spacing: 0) {
                        Text("LANDER").font(.system(size: 36, weight: .black, design: .rounded)).foregroundStyle(.white)
                    }
                    Text("BUDDY").font(.system(size: 14, weight: .bold)).tracking(4).foregroundStyle(Color.brand)
                }
                Spacer().frame(height: 40)
                // Tagline
                VStack(spacing: 10) {
                    Text("Spot injury risk").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Text("before it happens.").font(.title2.weight(.semibold)).foregroundStyle(Color.brand)
                    Text("Monitor your team's knee mechanics\nweek over week with just a phone camera.").font(.subheadline).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center).padding(.top, 4)
                }
                Spacer()
                // Buttons
                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { r in r.requestedScopes = [.fullName, .email] } onCompletion: { _ in
                        engine.userName = "Coach"; engine.teamName = "My Team"
                        withAnimation(.easeOut(duration: 0.3)) { engine.isSignedIn = true }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 14))

                    Button { withAnimation(.easeOut(duration: 0.3)) { engine.userName = "Coach"; engine.teamName = "My Team"; engine.isSignedIn = true } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill").font(.title2)
                            Text("Continue with Google").font(.system(size: 17, weight: .semibold))
                        }.frame(maxWidth: .infinity, minHeight: 54).background(.white).foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button { withAnimation(.easeOut(duration: 0.3)) { engine.userName = "Trainer"; engine.teamName = "Demo Team"; engine.isSignedIn = true } } label: {
                        Text("Skip — use demo data").font(.subheadline).foregroundStyle(Color.textSecondary)
                    }.padding(.top, 8)
                }.padding(.horizontal, 28).padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Main Tabs

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
                VStack(spacing: 14) {
                    let readiness = engine.computeReadiness()
                    let rc = readiness.filter { $0.status == .red }.count
                    let yc = readiness.filter { $0.status == .yellow }.count
                    let gc = readiness.filter { $0.status == .green }.count

                    // Summary
                    HStack(spacing: 10) {
                        StatusPill(count: gc, status: .green)
                        StatusPill(count: yc, status: .yellow)
                        StatusPill(count: rc, status: .red)
                        Spacer()
                    }.padding(.horizontal)

                    if rc > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusRed)
                            Text("\(rc) athlete\(rc > 1 ? "s" : "") at risk").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                            Spacer()
                        }.padding(12).background(Color.statusRed.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
                    }

                    // Athletes
                    ForEach(readiness) { item in
                        NavigationLink(destination: AthleteDetailView(athleteID: item.athlete.id)) {
                            AthleteCard(item: item)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal)
                }.padding(.vertical)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Readiness")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct StatusPill: View {
    let count: Int; let status: ReadinessStatus
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text("\(count)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
            Text(status.rawValue).font(.caption).foregroundStyle(Color.textSecondary)
        }.padding(.horizontal, 12).padding(.vertical, 8).background(Color.bgCard).clipShape(Capsule()).overlay(Capsule().stroke(status.color.opacity(0.3), lineWidth: 1))
    }
}

struct AthleteCard: View {
    let item: AthleteReadiness
    var body: some View {
        HStack(spacing: 14) {
            // Jersey circle
            ZStack {
                Circle().fill(Color.brand.opacity(0.12)).frame(width: 50, height: 50)
                Text("\(item.athlete.jerseyNumber)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Color.brand)
            }
            // Name
            VStack(alignment: .leading, spacing: 3) {
                Text(item.athlete.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(item.athlete.position).font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            // Delta
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%+.1f%%", -item.delta)).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(item.status.color)
                HStack(spacing: 3) {
                    Image(systemName: item.trend.icon).font(.system(size: 10))
                    Text(item.trend.rawValue).font(.system(size: 11))
                }.foregroundStyle(item.trend.color)
            }
            // Badge
            Text(item.status.rawValue).font(.system(size: 10, weight: .bold)).tracking(0.5)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(item.status.bgColor).foregroundStyle(item.status.color)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14).background(Color.bgCard).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
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
                VStack(spacing: 16) {
                    // Status header
                    VStack(spacing: 10) {
                        ZStack { Circle().fill(item.status.bgColor).frame(width: 56, height: 56); Circle().fill(item.status.color).frame(width: 18, height: 18) }
                        Text(item.status.rawValue).font(.headline).foregroundStyle(item.status.color)
                        Text(String(format: "Delta: %+.1f%%", -item.delta)).font(.subheadline).foregroundStyle(Color.textSecondary)
                    }.padding(20).frame(maxWidth: .infinity).background(Color.bgCard).clipShape(RoundedRectangle(cornerRadius: 16))

                    // Chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PERFORMANCE TREND").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Color.textSecondary)
                        ChartView(data: item.history, color: item.status.color).frame(height: 100)
                    }.padding(16).background(Color.bgCard).clipShape(RoundedRectangle(cornerRadius: 16))

                    // Stats
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(label: "BASELINE", value: String(format: "%.0f", item.baselineScore), icon: "target")
                        MetricCard(label: "CURRENT", value: String(format: "%.0f", item.currentScore), icon: "gauge.medium")
                        MetricCard(label: "TREND", value: item.trend.rawValue, icon: item.trend.icon)
                        MetricCard(label: "SESSIONS", value: "\(engine.sessions.filter { $0.athleteIDs.contains(athleteID) }.count)", icon: "calendar")
                    }

                    // History
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENT SESSIONS").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Color.textSecondary)
                        let recent = engine.sessions.filter { $0.athleteIDs.contains(athleteID) }.sorted { $0.date > $1.date }.prefix(5)
                        ForEach(Array(recent)) { s in
                            if let m = s.metrics[athleteID] {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.date, style: .date).font(.subheadline).foregroundStyle(.white)
                                        Text(s.isFresh ? "Fresh" : "Fatigued").font(.caption.weight(.medium))
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(s.isFresh ? Color.statusGreen.opacity(0.15) : Color.statusYellow.opacity(0.15))
                                            .foregroundStyle(s.isFresh ? Color.statusGreen : Color.statusYellow)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(String(format: "%.0f", m.compositeScore)).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.brand)
                                }.padding(.vertical, 6)
                                if s.id != recent.last?.id { Divider().overlay(Color.white.opacity(0.05)) }
                            }
                        }
                    }.padding(16).background(Color.bgCard).clipShape(RoundedRectangle(cornerRadius: 16))
                }.padding()
            }.background(Color.bgPrimary).navigationTitle(item.athlete.name)
        } else { Text("Not found").foregroundStyle(.white) }
    }
}

struct ChartView: View {
    let data: [Double]; let color: Color
    var body: some View {
        GeometryReader { geo in
            if data.count > 1 {
                let mn = (data.min() ?? 0) - 5, mx = (data.max() ?? 100) + 5, rng = mx - mn
                let step = geo.size.width / CGFloat(data.count - 1)
                Path { p in
                    for (i, v) in data.enumerated() { let x = CGFloat(i)*step; let y = geo.size.height - CGFloat((v-mn)/rng)*geo.size.height; if i==0 { p.move(to: .init(x: x, y: y)) } else { p.addLine(to: .init(x: x, y: y)) } }
                    p.addLine(to: .init(x: geo.size.width, y: geo.size.height)); p.addLine(to: .init(x: 0, y: geo.size.height)); p.closeSubpath()
                }.fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    for (i, v) in data.enumerated() { let x = CGFloat(i)*step; let y = geo.size.height - CGFloat((v-mn)/rng)*geo.size.height; if i==0 { p.move(to: .init(x: x, y: y)) } else { p.addLine(to: .init(x: x, y: y)) } }
                }.stroke(color, lineWidth: 2.5)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricCard: View {
    let label: String; let value: String; let icon: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.brand)
            Text(value).font(.title3.bold()).foregroundStyle(.white)
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Color.textSecondary)
        }.frame(maxWidth: .infinity).padding(16).background(Color.bgCard).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}



// MARK: - Capture Flow

struct CaptureFlowView: View {
    @Environment(DataEngine.self) private var engine
    @State private var captureDate = Date()
    @State private var isFresh = true
    @State private var selected: Set<UUID> = []
    @State private var processing = false
    @State private var done = false
    var body: some View {
        NavigationStack {
            Form {
                Section { DatePicker("Date", selection: $captureDate, displayedComponents: .date); Picker("Condition", selection: $isFresh) { Text("Fresh (Warm-up)").tag(true); Text("Fatigued (End of Practice)").tag(false) } } header: { Text("Session") }
                Section {
                    ForEach(engine.athletes) { a in
                        Button { if selected.contains(a.id) { selected.remove(a.id) } else { selected.insert(a.id) } } label: {
                            HStack { ZStack { Circle().fill(Color.brand.opacity(0.15)).frame(width: 30, height: 30); Text("\(a.jerseyNumber)").font(.caption.bold()).foregroundStyle(Color.brand) }; Text(a.name).foregroundStyle(.primary); Spacer(); if selected.contains(a.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand) } }
                        }
                    }
                } header: { Text("Athletes (\(selected.count))") }
                Section {
                    Button { processing = true; DispatchQueue.main.asyncAfter(deadline: .now()+1.5) { engine.runCapture(date: captureDate, isFresh: isFresh, athleteIDs: Array(selected)); processing = false; done = true } } label: {
                        HStack { Spacer(); if processing { ProgressView().tint(.black).padding(.trailing, 6); Text("Analyzing...").foregroundStyle(.black) } else { Image(systemName: "bolt.fill").foregroundStyle(.black); Text("Analyze Landing").foregroundStyle(.black) }; Spacer() }.font(.headline).padding(.vertical, 4)
                    }.listRowBackground(selected.isEmpty ? Color.gray.opacity(0.3) : Color.brand)
                    .disabled(selected.isEmpty || processing)
                }
            }
            .navigationTitle("New Capture")
            .alert("Done!", isPresented: $done) { Button("OK") { selected.removeAll() } } message: { Text("Processed \(selected.count) athlete(s).") }
        }
    }
}

// MARK: - Roster

struct RosterView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showAdd = false
    @State private var nn = ""; @State private var nj = ""; @State private var np = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(engine.athletes) { a in
                    HStack(spacing: 14) {
                        ZStack { Circle().fill(Color.brand.opacity(0.12)).frame(width: 42, height: 42); Text("\(a.jerseyNumber)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Color.brand) }
                        VStack(alignment: .leading, spacing: 2) { Text(a.name).font(.body.weight(.medium)); Text(a.position).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }.onDelete { idx in for i in idx { engine.removeAthlete(id: engine.athletes[i].id) } }
            }
            .navigationTitle("Roster")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.brand) } } }
            .sheet(isPresented: $showAdd) {
                NavigationStack { Form { TextField("Name", text: $nn); TextField("Jersey #", text: $nj).keyboardType(.numberPad); TextField("Position", text: $np) }.navigationTitle("Add Athlete").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { if let n = Int(nj), !nn.isEmpty { engine.addAthlete(name: nn, jerseyNumber: n, position: np); nn=""; nj=""; np=""; showAdd = false } }.disabled(nn.isEmpty) } } }
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
                ForEach(engine.sessions.sorted { $0.date > $1.date }) { s in
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(s.date, style: .date).font(.subheadline.weight(.medium)); HStack(spacing: 6) { Text(s.isFresh ? "Fresh" : "Fatigued").font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2).background(s.isFresh ? Color.statusGreen.opacity(0.12) : Color.statusYellow.opacity(0.12)).foregroundStyle(s.isFresh ? Color.statusGreen : Color.statusYellow).clipShape(Capsule()); Text("\(s.athleteIDs.count) athletes").font(.caption).foregroundStyle(.secondary) } }; Spacer() }.padding(.vertical, 3)
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
                Section("Team") { HStack { Text("Name"); Spacer(); Text(engine.teamName).foregroundStyle(.secondary) }; HStack { Text("User"); Spacer(); Text(engine.userName).foregroundStyle(.secondary) } }
                Section("Risk Thresholds") { HStack { Text("Caution (%)"); Spacer(); TextField("", value: $engine.thresholds.yellowDelta, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 50) }; HStack { Text("High Risk (%)"); Spacer(); TextField("", value: $engine.thresholds.redDelta, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 50) } }
                Section("About") { HStack { Text("Version"); Spacer(); Text("1.0.0").foregroundStyle(.secondary) }; HStack { Text("Engine"); Spacer(); Text("LANDER CV").foregroundStyle(.secondary) } }
                Section { Button("Reset Demo Data") { engine.seedDemoData() }; Button("Sign Out") { withAnimation { engine.isSignedIn = false } }.foregroundStyle(.red) }
            }.navigationTitle("Settings")
        }
    }
}
