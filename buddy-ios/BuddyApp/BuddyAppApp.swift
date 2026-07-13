import SwiftUI
import AuthenticationServices
import AVFoundation
import AVKit
import UserNotifications

// NOTE: Info.plist must include:
// NSCameraUsageDescription - "LANDER Buddy needs camera access to record landing videos for analysis."
// NSMicrophoneUsageDescription - "LANDER Buddy needs microphone access to record audio with landing videos."

// MARK: - Color Theme
extension Color {
    static let brand = Color(red: 0.75, green: 1.0, blue: 0.0)
    static let brandGlow = Color(red: 0.75, green: 1.0, blue: 0.0).opacity(0.4)
    static let bgPrimary = Color(red: 0.04, green: 0.06, blue: 0.1)
    static let bgCard = Color(red: 0.08, green: 0.1, blue: 0.15)
    static let bgCardLight = Color(red: 0.12, green: 0.14, blue: 0.2)
    static let statusGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let statusYellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let statusRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let textSecondary = Color(white: 0.55)
}

// MARK: - Data Models
enum AthleteStatus: String, Codable, Equatable {
    case good = "Good", caution = "Caution", atRisk = "At Risk", buildingBaseline = "Building Baseline"
}
enum AthleteTrend: String, Codable, Equatable {
    case improving = "Improving", stable = "Stable", worsening = "Worsening"
}

struct DataPoint: Identifiable, Codable, Equatable {
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

struct AthleteReadiness: Identifiable, Equatable {
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

// MARK: - Camera Sheet Item
struct CameraSheetItem: Identifiable {
    let id: UUID
}


// MARK: - Persistence
struct PersistenceManager {
    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var dataFileURL: URL {
        documentsURL.appendingPathComponent("buddy_athletes_v3.json")
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
    var sportType = "Soccer"
    var cautionThreshold: Double = 10.0
    var atRiskThreshold: Double = 18.0
    var showSplash = false

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
        get { UserDefaults.standard.string(forKey: "sportType") ?? "Soccer" }
        set { UserDefaults.standard.set(newValue, forKey: "sportType") }
    }
    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    init() {
        if let saved = PersistenceManager.loadAthletes(), !saved.isEmpty {
            athletes = saved
        } else {
            loadDemoData()
        }
        if !storedTeamName.isEmpty { teamName = storedTeamName }
        if !storedCoachName.isEmpty { userName = storedCoachName }
        if !storedSportType.isEmpty { sportType = storedSportType }
    }

    func save() { PersistenceManager.saveAthletes(athletes) }


    func loadDemoData() {
        let cal = Calendar.current
        let now = Date()
        func weeksAgo(_ w: Int, day: Int) -> Date {
            cal.date(byAdding: .day, value: -(w * 7) + day, to: now)!
        }

        // Maya = Good + Stable (~5%)
        var maya: [DataPoint] = []
        for w in (0..<6).reversed() {
            maya.append(DataPoint(date: weeksAgo(w, day: 0), value: 6.0 + Double.random(in: -0.15...0.15), isFresh: true))
            maya.append(DataPoint(date: weeksAgo(w, day: 2), value: 6.3 + Double.random(in: -0.1...0.15), isFresh: false))
        }
        // Carlos = Good + Improving (12% -> 6%)
        var carlos: [DataPoint] = []
        for w in (0..<6).reversed() {
            let progress = Double(5 - w) / 5.0
            carlos.append(DataPoint(date: weeksAgo(w, day: 0), value: 7.0 + Double.random(in: -0.1...0.1), isFresh: true))
            carlos.append(DataPoint(date: weeksAgo(w, day: 2), value: 7.0 + (0.84 - progress * 0.42) + Double.random(in: -0.08...0.08), isFresh: false))
        }
        // Aisha = Caution + Worsening (8% -> 14%)
        var aisha: [DataPoint] = []
        for w in (0..<6).reversed() {
            let progress = Double(5 - w) / 5.0
            aisha.append(DataPoint(date: weeksAgo(w, day: 0), value: 7.5 + Double.random(in: -0.1...0.1), isFresh: true))
            aisha.append(DataPoint(date: weeksAgo(w, day: 2), value: 7.5 + (0.6 + progress * 0.45) + Double.random(in: -0.06...0.08), isFresh: false))
        }
        // Jake = At Risk + Worsening (12% -> 24%)
        var jake: [DataPoint] = []
        for w in (0..<6).reversed() {
            let progress = Double(5 - w) / 5.0
            jake.append(DataPoint(date: weeksAgo(w, day: 0), value: 8.0 + Double.random(in: -0.1...0.1), isFresh: true))
            jake.append(DataPoint(date: weeksAgo(w, day: 2), value: 8.0 + (0.96 + progress * 0.96) + Double.random(in: -0.08...0.12), isFresh: false))
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
            let recent = Array(deltaHistory.suffix(3))
            let diff = recent.last!.value - recent.first!.value
            if diff > 2 { trend = .worsening } else if diff < -2 { trend = .improving } else { trend = .stable }
        } else { trend = .stable }

        let recommendation: String
        switch (status, trend) {
        case (.atRisk, .worsening): recommendation = "Reduce load immediately — landing degraded \(Int(degradation))% under fatigue, worsening over 4 weeks. Consider rest day before next session."
        case (.atRisk, _): recommendation = "High degradation at \(Int(degradation))%. Reduce jumping and cutting volume this week."
        case (.caution, .worsening): recommendation = "Monitor closely — degradation trending up to \(Int(degradation))%. Ease plyometric volume."
        case (.caution, _): recommendation = "Moderate degradation at \(Int(degradation))%. Maintain current load and monitor weekly."
        case (.good, .worsening): recommendation = "Currently good but trend worsening. Watch next 2 sessions closely."
        case (.good, .improving): recommendation = "Excellent — degradation reduced. Maintain current training program."
        default: recommendation = "On track — maintain normal training load."
        }

        let flexionHistory = athlete.sessions.map {
            DataPoint(date: $0.date, value: 55 + Double.random(in: -3...3), isFresh: $0.isFresh)
        }

        return AthleteReadiness(
            id: athlete.id, name: athlete.name, jersey: athlete.jersey, position: athlete.position,
            fatigueDegradationPct: max(0, degradation), status: status, trend: trend,
            recommendation: recommendation, valgusHistory: athlete.sessions,
            flexionHistory: flexionHistory, deltaHistory: deltaHistory,
            baselineValgus: baselineValgus, latestFatiguedValgus: latestFatigued,
            sessionCount: athlete.sessions.count, allSessions: athlete.sessions
        )
    }


    var allReadiness: [AthleteReadiness] {
        athletes.map { readiness(for: $0) }.sorted { $0.fatigueDegradationPct > $1.fatigueDegradationPct }
    }

    var teamScore: Int {
        let r = allReadiness; guard !r.isEmpty else { return 100 }
        let avg = r.map { max(0, 100 - $0.fatigueDegradationPct * 3) }.reduce(0, +) / Double(r.count)
        return Int(min(100, max(0, avg)))
    }

    var statusSummary: (good: Int, caution: Int, atRisk: Int) {
        let r = allReadiness
        return (r.filter { $0.status == .good }.count,
                r.filter { $0.status == .caution }.count,
                r.filter { $0.status == .atRisk }.count)
    }

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

    func resetDemo() { athletes.removeAll(); loadDemoData() }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { self.notificationsEnabled = granted }
        }
    }

    func scheduleAtRiskNotification(name: String, degradation: Int) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Landing Risk Alert"
        content.body = "\(name)'s landing degraded \(degradation)% — review recommended"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}


// MARK: - App Entry
@main
struct BuddyAppApp: App {
    @State private var engine = DataEngine()
    var body: some Scene {
        WindowGroup {
            Group {
                if engine.showSplash {
                    AnimatedSplashView()
                        .transition(.opacity)
                } else if engine.isSignedIn {
                    if engine.hasCompletedOnboarding {
                        MainTabView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        TeamSetupView()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: engine.isSignedIn)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: engine.hasCompletedOnboarding)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: engine.showSplash)
            .environment(engine)
            .preferredColorScheme(.dark)
        }
    }
}


// MARK: - Animated Splash
struct AnimatedSplashView: View {
    @Environment(DataEngine.self) private var engine
    @State private var logoScale: CGFloat = 0.3
    @State private var glowRadius: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var landerOpacity: Double = 0
    @State private var buddyOpacity: Double = 0
    @State private var ringRotation: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    // Pulsing glow ring
                    Circle()
                        .stroke(Color.brand.opacity(glowOpacity), lineWidth: 3)
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.brand.opacity(glowOpacity * 0.8), radius: glowRadius)
                        .rotationEffect(.degrees(ringRotation))
                    // Logo icon
                    Image(systemName: "figure.run")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(Color.brand)
                        .shadow(color: Color.brandGlow, radius: glowRadius)
                        .scaleEffect(logoScale)
                }
                Text("LANDER")
                    .font(.system(size: 38, weight: .black, design: .default))
                    .foregroundStyle(.white)
                    .opacity(landerOpacity)
                Text("BUDDY")
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(Color.brand)
                    .opacity(buddyOpacity)
                    .shadow(color: Color.brandGlow, radius: 4)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                logoScale = 1.0
            }
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                glowRadius = 20; glowOpacity = 0.7
            }
            withAnimation(.linear(duration: 2.0).delay(0.1)) {
                ringRotation = 360
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.5)) {
                landerOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.8)) {
                buddyOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    engine.showSplash = false
                }
            }
        }
    }
}


// MARK: - Onboarding (Sign In)
struct OnboardingView: View {
    @Environment(DataEngine.self) private var engine
    @State private var logoScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            // Subtle radial gradient glow behind logo
            RadialGradient(colors: [Color.brand.opacity(0.08), .clear], center: .center, startRadius: 20, endRadius: 250)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(Color.brand)
                        .shadow(color: Color.brandGlow, radius: 12)
                        .scaleEffect(logoScale)
                    Text("LANDER")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(.white)
                    Text("BUDDY")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.brand)
                    Text("Spot injury risk before it happens")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 4)
                }
                Spacer()
                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in
                        triggerSignIn()
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .cornerRadius(14)
                    .padding(.horizontal, 36)

                    Button { triggerSignIn() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill").font(.title3)
                            Text("Continue with Google").font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.bgCard).cornerRadius(14)
                        .foregroundStyle(.white)
                    }.padding(.horizontal, 36)

                    Button("Skip — use demo data") {
                        engine.hasCompletedOnboarding = true
                        engine.showSplash = true
                        engine.isSignedIn = true
                    }
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                    .padding(.top, 4)
                }
                .opacity(contentOpacity)
                Spacer().frame(height: 50)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) { logoScale = 1.0 }
            withAnimation(.easeIn(duration: 0.5).delay(0.3)) { contentOpacity = 1.0 }
        }
    }

    private func triggerSignIn() {
        engine.showSplash = true
        engine.isSignedIn = true
    }
}


// MARK: - Team Setup (Post Sign-In Onboarding)
struct TeamSetupView: View {
    @Environment(DataEngine.self) private var engine
    @State private var teamNameInput = ""
    @State private var coachNameInput = ""
    @State private var selectedSport = "Soccer"
    @State private var appeared = false
    private let sportOptions = ["Soccer", "Basketball", "Volleyball", "Track", "Football", "Other"]

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            RadialGradient(colors: [Color.brand.opacity(0.05), .clear], center: .top, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 52)).foregroundStyle(Color.brand)
                    .shadow(color: Color.brandGlow, radius: 8)
                Text("Set Up Your Team")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text("Tell us about your team to get started")
                    .font(.subheadline).foregroundStyle(Color.textSecondary)

                VStack(spacing: 18) {
                    FloatingTextField(label: "Team Name", placeholder: "e.g. FC Thunder", text: $teamNameInput)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sport").font(.caption.bold()).foregroundStyle(Color.textSecondary)
                        Picker("Sport", selection: $selectedSport) {
                            ForEach(sportOptions, id: \.self) { Text($0) }
                        }.pickerStyle(.segmented).tint(Color.brand)
                    }
                    FloatingTextField(label: "Coach Name", placeholder: "e.g. Coach Davis", text: $coachNameInput)
                }.padding(.horizontal, 28)

                Spacer()
                Button {
                    engine.storedTeamName = teamNameInput.isEmpty ? "My Team" : teamNameInput
                    engine.storedCoachName = coachNameInput.isEmpty ? "Coach" : coachNameInput
                    engine.storedSportType = selectedSport
                    engine.teamName = engine.storedTeamName
                    engine.userName = engine.storedCoachName
                    engine.sportType = selectedSport
                    engine.requestNotificationPermission()
                    engine.hasCompletedOnboarding = true
                    engine.showSplash = true
                } label: {
                    Text("Get Started")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.brand).foregroundStyle(.black)
                        .cornerRadius(14)
                }.padding(.horizontal, 28)
                Spacer().frame(height: 50)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }
}

struct FloatingTextField: View {
    let label: String; let placeholder: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold()).foregroundStyle(Color.textSecondary)
            TextField(placeholder, text: $text)
                .padding(14).background(Color.bgCard).cornerRadius(12)
                .foregroundStyle(.white).overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.bgCardLight, lineWidth: 1)
                )
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
        }
        .tint(Color.brand)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear { withAnimation(.easeInOut(duration: 0.4)) { appeared = true } }
    }
}

// MARK: - Card Press Style
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}


// MARK: - Shared UI Components
struct JerseyCircle: View {
    let number: Int; let size: CGFloat; var glowing: Bool = false
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brand.opacity(0.15))
                .frame(width: size, height: size)
            if glowing {
                Circle()
                    .stroke(Color.statusRed.opacity(0.6), lineWidth: 2)
                    .frame(width: size, height: size)
                    .shadow(color: Color.statusRed.opacity(0.5), radius: 6)
            }
            Text("#\(number)")
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(Color.brand)
        }
    }
}

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
        Text(status.rawValue).font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: status)
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
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(trend.rawValue).font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}


// MARK: - Sparkline (Inverted Y: higher = worse = down)
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
                        let y = geo.size.height * CGFloat((val - mn) / range)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(color, lineWidth: 1.8)
            }
        }
    }
}

// MARK: - Area Chart (for team trend)
struct AreaChartView: View {
    let data: [DataPoint]
    let lineColor: Color
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let values = data.map(\.value)
            let mn = (values.min() ?? 0) - 1
            let mx = (values.max() ?? 1) + 1
            let range = mx - mn == 0 ? 1 : mx - mn
            let h = geo.size.height; let w = geo.size.width

            ZStack(alignment: .leading) {
                // Y-axis labels
                VStack {
                    Text(String(format: "%.0f%%", mx)).font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", mn)).font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                }.frame(width: 30)

                // Chart area
                ZStack {
                    // Gradient fill
                    Path { path in
                        for (i, val) in values.enumerated() {
                            let x = 30 + (w - 30) * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                            let y = h * (1 - CGFloat((val - mn) / range))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: 30, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [lineColor.opacity(0.35), lineColor.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    // Line
                    Path { path in
                        for (i, val) in values.enumerated() {
                            let x = 30 + (w - 30) * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                            let y = h * (1 - CGFloat((val - mn) / range))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }.stroke(lineColor, lineWidth: 2.5)

                    // 0% baseline
                    if mn < 0 && mx > 0 {
                        let zeroY = h * (1 - CGFloat((0 - mn) / range))
                        Path { p in p.move(to: CGPoint(x: 30, y: zeroY)); p.addLine(to: CGPoint(x: w, y: zeroY)) }
                            .stroke(Color.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.2)) { appeared = true } }
    }
}


// MARK: - Line Chart (with axis labels, markers, baseline, gradient fill)
struct LineChartView: View {
    let data: [DataPoint]
    let baselineValue: Double?
    let lineColor: Color
    let title: String
    let unit: String
    var showFreshFatigued: Bool = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(Color.textSecondary)
            HStack(spacing: 0) {
                let values = data.map(\.value)
                let allVals = baselineValue != nil ? values + [baselineValue!] : values
                let mn = (allVals.min() ?? 0) - 0.5
                let mx = (allVals.max() ?? 1) + 0.5
                VStack {
                    Text(String(format: "%.1f", mx)).font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f", mn)).font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                }.frame(width: 30, height: 130)

                GeometryReader { geo in
                    let range = mx - mn == 0 ? 1 : mx - mn
                    let h = geo.size.height; let w = geo.size.width
                    ZStack {
                        // Gradient fill
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
                        }.fill(LinearGradient(colors: [lineColor.opacity(0.25), lineColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                        // Line
                        Path { path in
                            for (i, val) in values.enumerated() {
                                let x = w * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                                let y = h * (1 - CGFloat((val - mn) / range))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(lineColor, lineWidth: 2.5)

                        // Fresh/Fatigued dots
                        if showFreshFatigued {
                            ForEach(Array(data.enumerated()), id: \.offset) { i, dp in
                                let x = w * CGFloat(i) / CGFloat(max(data.count - 1, 1))
                                let y = h * (1 - CGFloat((dp.value - mn) / range))
                                Circle()
                                    .fill(dp.isFresh ? Color.statusGreen : Color.statusYellow)
                                    .frame(width: dp.isFresh ? 5 : 6, height: dp.isFresh ? 5 : 6)
                                    .position(x: x, y: y)
                            }
                        }

                        // Baseline dashed line
                        if let bl = baselineValue {
                            let by = h * (1 - CGFloat((bl - mn) / range))
                            Path { p in p.move(to: CGPoint(x: 0, y: by)); p.addLine(to: CGPoint(x: w, y: by)) }
                                .stroke(Color.textSecondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                    }
                }.frame(height: 130)
            }
            // X-axis labels
            if let first = data.first, let last = data.last {
                HStack {
                    Spacer().frame(width: 30)
                    Text(first.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(last.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8)).foregroundStyle(Color.textSecondary)
                }
            }
            // Legend
            HStack(spacing: 8) {
                if baselineValue != nil {
                    HStack(spacing: 3) {
                        Rectangle().fill(Color.textSecondary).frame(width: 12, height: 1)
                        Text("Baseline").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                    }
                }
                if showFreshFatigued {
                    HStack(spacing: 3) {
                        Circle().fill(Color.statusGreen).frame(width: 5, height: 5)
                        Text("Fresh").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color.statusYellow).frame(width: 5, height: 5)
                        Text("Fatigued").font(.system(size: 9)).foregroundStyle(Color.textSecondary)
                    }
                }
            }.padding(.leading, 30)
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear { withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appeared = true } }
    }
}


// MARK: - Dashboard (Complete Redesign)
struct DashboardView: View {
    @Environment(DataEngine.self) private var engine
    @State private var heroAppeared = false
    @State private var alertAppeared = false
    @State private var trendAppeared = false
    @State private var listAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Hero Card: Team Readiness Score with circular progress ring
                    HeroScoreCard(score: engine.teamScore, summary: engine.statusSummary)
                        .padding(.horizontal)
                        .opacity(heroAppeared ? 1 : 0)
                        .offset(y: heroAppeared ? 0 : 16)

                    // Alert Section: At Risk athletes
                    let atRiskAthletes = engine.allReadiness.filter { $0.status == .atRisk }
                    if !atRiskAthletes.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(atRiskAthletes) { athlete in
                                AlertCard(readiness: athlete)
                            }
                        }
                        .padding(.horizontal)
                        .opacity(alertAppeared ? 1 : 0)
                        .offset(y: alertAppeared ? 0 : 12)
                    }

                    // Team Trend Area Chart
                    if engine.teamDeltaTrend.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Team Avg Fatigue Delta")
                                    .font(.caption.bold()).foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("6 weeks")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.brand.opacity(0.7))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.brand.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            AreaChartView(data: engine.teamDeltaTrend, lineColor: .brand)
                                .frame(height: 110)
                        }
                        .padding(14)
                        .background(Color.bgCard)
                        .cornerRadius(14)
                        .padding(.horizontal)
                        .opacity(trendAppeared ? 1 : 0)
                        .offset(y: trendAppeared ? 0 : 12)
                    }

                    // Athlete List
                    VStack(spacing: 10) {
                        ForEach(engine.allReadiness) { r in
                            NavigationLink(value: r.id) {
                                AthleteRow(readiness: r)
                            }.buttonStyle(CardPressStyle())
                        }
                    }
                    .padding(.horizontal)
                    .opacity(listAppeared ? 1 : 0)
                    .offset(y: listAppeared ? 0 : 10)
                }
                .padding(.vertical)
            }
            .refreshable { engine.resetDemo() }
            .background(Color.bgPrimary)
            .navigationTitle("Dashboard")
            .navigationDestination(for: UUID.self) { id in
                AthleteDetailView(athleteID: id)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) { heroAppeared = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { alertAppeared = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) { trendAppeared = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) { listAppeared = true }
        }
    }
}


// MARK: - Hero Score Card
struct HeroScoreCard: View {
    let score: Int
    let summary: (good: Int, caution: Int, atRisk: Int)
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 14) {
            Text("TEAM READINESS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .tracking(1.5)
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.bgCardLight, lineWidth: 10)
                    .frame(width: 110, height: 110)
                // Progress ring
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        AngularGradient(colors: [Color.brand, Color.statusGreen, Color.brand], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.brand.opacity(0.5), radius: 8)
                // Score number
                Text("\(score)")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            // Status summary
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Color.statusGreen).frame(width: 8, height: 8)
                    Text("\(summary.good) Good").font(.caption).foregroundStyle(Color.textSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.statusYellow).frame(width: 8, height: 8)
                    Text("\(summary.caution) Caution").font(.caption).foregroundStyle(Color.textSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.statusRed).frame(width: 8, height: 8)
                    Text("\(summary.atRisk) At Risk").font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.bgCard)
                .shadow(color: Color.brand.opacity(0.08), radius: 20, y: 8)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                ringProgress = CGFloat(score) / 100.0
            }
        }
    }
}

// MARK: - Alert Card
struct AlertCard: View {
    let readiness: AthleteReadiness
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3).foregroundStyle(Color.statusRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(readiness.name).font(.subheadline.bold()).foregroundStyle(.white)
                Text(readiness.recommendation).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(2)
            }
            Spacer()
            Text("\(Int(readiness.fatigueDegradationPct))%")
                .font(.title3.bold()).foregroundStyle(Color.statusRed)
        }
        .padding(14)
        .background(Color.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.statusRed.opacity(pulsing ? 0.6 : 0.25), lineWidth: 1.5)
        )
        .cornerRadius(14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}


// MARK: - Athlete Row
struct AthleteRow: View {
    let readiness: AthleteReadiness
    var body: some View {
        HStack(spacing: 12) {
            JerseyCircle(number: readiness.jersey, size: 44, glowing: readiness.status == .atRisk)
            VStack(alignment: .leading, spacing: 3) {
                Text(readiness.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                Text(readiness.position).font(.caption).foregroundStyle(Color.textSecondary)
                Text(readiness.recommendation).font(.system(size: 10)).foregroundStyle(Color.textSecondary.opacity(0.7)).lineLimit(1)
            }
            Spacer()
            // Sparkline
            SparklineView(
                points: readiness.deltaHistory.suffix(5).map(\.value),
                color: readiness.trend == .worsening ? Color.statusRed : readiness.trend == .improving ? Color.statusGreen : Color.textSecondary
            ).frame(width: 44, height: 22)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(readiness.fatigueDegradationPct))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        readiness.status == .atRisk ? Color.statusRed :
                        readiness.status == .caution ? Color.statusYellow : Color.statusGreen
                    )
                HStack(spacing: 4) {
                    StatusBadge(status: readiness.status)
                    TrendBadge(trend: readiness.trend)
                }
            }
        }
        .padding(14)
        .background(Color.bgCard)
        .cornerRadius(14)
    }
}


// MARK: - Athlete Detail (Major Upgrade)
struct AthleteDetailView: View {
    @Environment(DataEngine.self) private var engine
    let athleteID: UUID
    private var r: AthleteReadiness? { engine.allReadiness.first { $0.id == athleteID } }
    @State private var chartsAppeared = false
    @State private var statsAppeared = false

    var body: some View {
        ScrollView {
            if let r = r {
                VStack(spacing: 18) {
                    // Sticky Header
                    VStack(spacing: 10) {
                        JerseyCircle(number: r.jersey, size: 72, glowing: r.status == .atRisk)
                        Text(r.name).font(.title2.bold()).foregroundStyle(.white)
                        Text(r.position).font(.subheadline).foregroundStyle(Color.textSecondary)
                        HStack(spacing: 10) {
                            StatusBadge(status: r.status)
                            TrendBadge(trend: r.trend)
                        }
                    }.padding(.top, 8)

                    // Recommendation Card
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.title3).foregroundStyle(Color.brand)
                        Text(r.recommendation)
                            .font(.callout).foregroundStyle(.white)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgCard)
                    .overlay(
                        HStack {
                            Rectangle().fill(Color.brand).frame(width: 3)
                            Spacer()
                        }
                    )
                    .cornerRadius(14)
                    .padding(.horizontal)

                    // Charts (staggered fade-in)
                    LineChartView(data: r.valgusHistory, baselineValue: r.baselineValgus,
                        lineColor: .brand, title: "Knee Valgus", unit: "degrees", showFreshFatigued: true)
                        .padding(.horizontal)
                        .opacity(chartsAppeared ? 1 : 0)
                        .offset(y: chartsAppeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.1), value: chartsAppeared)

                    LineChartView(data: r.flexionHistory, baselineValue: 55.0,
                        lineColor: Color(red: 0.3, green: 0.6, blue: 1.0), title: "Knee Flexion", unit: "degrees")
                        .padding(.horizontal)
                        .opacity(chartsAppeared ? 1 : 0)
                        .offset(y: chartsAppeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.25), value: chartsAppeared)

                    LineChartView(data: r.deltaHistory, baselineValue: 0,
                        lineColor: Color.statusRed, title: "Fatigue Delta", unit: "% degradation")
                        .padding(.horizontal)
                        .opacity(chartsAppeared ? 1 : 0)
                        .offset(y: chartsAppeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.4), value: chartsAppeared)

                    // Stats Grid (2x2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCell(label: "Baseline Valgus", value: String(format: "%.1f°", r.baselineValgus), color: .brand)
                        StatCell(label: "Latest Fatigued", value: String(format: "%.1f°", r.latestFatiguedValgus), color: .statusYellow)
                        StatCell(label: "Degradation", value: "\(Int(r.fatigueDegradationPct))%",
                            color: r.status == .atRisk ? .statusRed : r.status == .caution ? .statusYellow : .statusGreen)
                        StatCell(label: "Sessions", value: "\(r.sessionCount)", color: .brand)
                    }
                    .padding(.horizontal)
                    .opacity(statsAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.5), value: statsAppeared)

                    // Session History
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session History").font(.headline).foregroundStyle(.white)
                        ForEach(r.allSessions.reversed()) { s in
                            SessionHistoryRow(session: s, baselineValgus: r.baselineValgus,
                                cautionThreshold: engine.cautionThreshold, atRiskThreshold: engine.atRiskThreshold)
                        }
                    }
                    .padding(16)
                    .background(Color.bgCard)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                .padding(.bottom, 30)
            } else {
                VStack {
                    Spacer().frame(height: 100)
                    Text("Athlete not found").foregroundStyle(Color.textSecondary)
                }
            }
        }
        .background(Color.bgPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "LANDER Buddy — \(r?.name ?? "Athlete") Report",
                    subject: Text("Athlete Report"),
                    message: Text("\(r?.name ?? "") — \(Int(r?.fatigueDegradationPct ?? 0))% degradation, Status: \(r?.status.rawValue ?? "")")) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Color.brand)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { chartsAppeared = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) { statsAppeared = true }
        }
    }
}

struct StatCell: View {
    let label: String; let value: String; var color: Color = .white
    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(value).font(.title3.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity).padding(14)
        .background(Color.bgCard).cornerRadius(12)
    }
}

struct SessionHistoryRow: View {
    let session: DataPoint
    let baselineValgus: Double
    let cautionThreshold: Double
    let atRiskThreshold: Double

    private var valueColor: Color {
        guard !session.isFresh, baselineValgus > 0 else { return .white }
        let delta = ((session.value - baselineValgus) / baselineValgus) * 100
        if delta > atRiskThreshold { return Color.statusRed }
        else if delta > cautionThreshold { return Color.statusYellow }
        else { return Color.statusGreen }
    }

    var body: some View {
        HStack {
            Text(session.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption).foregroundStyle(Color.textSecondary)
            Spacer()
            Text(session.isFresh ? "Fresh" : "Fatigued").font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(session.isFresh ? Color.statusGreen.opacity(0.15) : Color.statusYellow.opacity(0.15))
                .foregroundStyle(session.isFresh ? Color.statusGreen : Color.statusYellow)
                .clipShape(Capsule())
            Text(String(format: "%.1f°", session.value))
                .font(.caption.bold()).foregroundStyle(valueColor)
                .frame(width: 44, alignment: .trailing)
        }
    }
}


// MARK: - Camera Integration
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


// MARK: - Capture Flow (Polished 4-Step)
struct CaptureFlowView: View {
    @Environment(DataEngine.self) private var engine
    @State private var step = 1
    @State private var selectedDate = Date()
    @State private var isFresh = true
    @State private var selectedAthleteIDs: Set<UUID> = []
    @State private var captureItems: [CaptureItem] = []
    @State private var consentGiven = false
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
                    // Animated progress bar
                    HStack(spacing: 5) {
                        ForEach(1...4, id: \.self) { s in
                            Capsule()
                                .fill(s <= step ? Color.brand : Color.bgCardLight)
                                .frame(height: 4)
                                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step)
                        }
                    }.padding(.horizontal).padding(.top, 8)

                    // Step label
                    HStack {
                        Text(stepTitle).font(.caption.bold()).foregroundStyle(Color.brand)
                        Spacer()
                        Text("Step \(step) of 4").font(.caption).foregroundStyle(Color.textSecondary)
                    }.padding(.horizontal).padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 20) {
                            Group {
                                switch step {
                                case 1: captureStep1
                                case 2: captureStep2
                                case 3: captureStep3
                                default: captureStep4
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        }.padding()
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step)
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

    private var stepTitle: String {
        switch step {
        case 1: return "SESSION DETAILS"
        case 2: return "VIDEO UPLOAD"
        case 3: return "PROCESSING"
        default: return "RESULTS"
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


    // Step 1: Date + Type + Athlete Selection
    private var captureStep1: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Session Date").font(.subheadline.bold()).foregroundStyle(.white)
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden().tint(.brand)
                    .padding(12).background(Color.bgCard).cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Condition").font(.subheadline.bold()).foregroundStyle(.white)
                HStack(spacing: 12) {
                    ConditionButton(title: "Fresh", selected: isFresh) { isFresh = true }
                    ConditionButton(title: "Fatigued", selected: !isFresh) { isFresh = false }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Select Athletes").font(.subheadline.bold()).foregroundStyle(.white)
                ForEach(engine.athletes) { a in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedAthleteIDs.contains(a.id) { selectedAthleteIDs.remove(a.id) }
                            else { selectedAthleteIDs.insert(a.id) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            JerseyCircle(number: a.jersey, size: 36)
                            Text(a.name).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            ZStack {
                                Circle().stroke(selectedAthleteIDs.contains(a.id) ? Color.brand : Color.textSecondary.opacity(0.4), lineWidth: 2)
                                    .frame(width: 24, height: 24)
                                if selectedAthleteIDs.contains(a.id) {
                                    Circle().fill(Color.brand).frame(width: 24, height: 24)
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                                }
                            }
                        }.padding(12).background(Color.bgCard).cornerRadius(12)
                    }
                }
            }

            Spacer().frame(height: 8)
            Button {
                captureItems = selectedAthleteIDs.compactMap { id in
                    guard let a = engine.athletes.first(where: { $0.id == id }) else { return nil }
                    return CaptureItem(id: a.id, name: a.name)
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { step = 2 }
            } label: {
                HStack {
                    Text("Next").font(.headline)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity).padding(15)
                .background(selectedAthleteIDs.isEmpty ? Color.bgCardLight : Color.brand)
                .foregroundStyle(selectedAthleteIDs.isEmpty ? Color.textSecondary : .black)
                .cornerRadius(14)
            }.disabled(selectedAthleteIDs.isEmpty)
        }
    }

    // Step 2: Video Upload per athlete
    private var captureStep2: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record or select a landing video for each athlete.")
                .font(.caption).foregroundStyle(Color.textSecondary)

            ForEach($captureItems) { $item in
                HStack(spacing: 12) {
                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(item.name).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    if item.videoAttached {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2).foregroundStyle(Color.statusGreen)
                    } else {
                        Button {
                            actionSheetItemID = item.id
                            showVideoActionSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video.badge.plus").font(.caption)
                                Text("Add Video").font(.caption.bold())
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.brand.opacity(0.15))
                            .foregroundStyle(Color.brand)
                            .cornerRadius(8)
                        }
                    }
                }.padding(12).background(Color.bgCard).cornerRadius(12)
            }
            .confirmationDialog("Add Video", isPresented: $showVideoActionSheet, titleVisibility: .visible) {
                Button("Record with Camera") {
                    if let id = actionSheetItemID { checkCameraAndRecord(for: id) }
                }
                Button("Choose from Library") {
                    if let id = actionSheetItemID {
                        cameraSourceType = .photoLibrary
                        showCameraFor = CameraSheetItem(id: id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            // Consent toggle
            HStack(spacing: 12) {
                Toggle("", isOn: $consentGiven).labelsHidden().tint(Color.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Consent Confirmed").font(.subheadline.bold()).foregroundStyle(.white)
                    Text("All athletes have provided consent for video analysis.")
                        .font(.caption2).foregroundStyle(Color.textSecondary)
                }
            }.padding(.top, 8)

            let allAttached = captureItems.allSatisfy(\.videoAttached)
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { step = 1 }
                } label: {
                    Text("Back").font(.subheadline.bold())
                        .padding(14).frame(maxWidth: .infinity)
                        .background(Color.bgCardLight).foregroundStyle(.white).cornerRadius(14)
                }
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { step = 3 }
                    startAnalysis()
                } label: {
                    HStack {
                        Text("Analyze").font(.headline)
                        Image(systemName: "wand.and.stars")
                    }
                    .frame(maxWidth: .infinity).padding(15)
                    .background(allAttached && consentGiven ? Color.brand : Color.bgCardLight)
                    .foregroundStyle(allAttached && consentGiven ? .black : Color.textSecondary)
                    .cornerRadius(14)
                }.disabled(!allAttached || !consentGiven)
            }
        }
    }


    // Step 3: Processing with animated checkmarks
    private var captureStep3: some View {
        VStack(spacing: 18) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36)).foregroundStyle(Color.brand)
                .shadow(color: Color.brandGlow, radius: 8)
            Text("Analyzing Landing Mechanics")
                .font(.headline).foregroundStyle(.white)
            Text("Running pose estimation and biomechanics analysis...")
                .font(.caption).foregroundStyle(Color.textSecondary)

            VStack(spacing: 10) {
                ForEach(captureItems) { item in
                    HStack(spacing: 12) {
                        Text(item.name).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        if item.done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3).foregroundStyle(Color.statusGreen)
                                .scaleEffect(item.done ? 1.0 : 0.3)
                                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: item.done)
                        } else if item.processing {
                            ProgressView().tint(Color.brand).scaleEffect(0.9)
                        } else {
                            Circle().fill(Color.bgCardLight).frame(width: 22, height: 22)
                        }
                    }.padding(14).background(Color.bgCard).cornerRadius(12)
                }
            }

            if captureItems.allSatisfy(\.done) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { step = 4 }
                } label: {
                    HStack {
                        Text("View Results").font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity).padding(15)
                    .background(Color.brand).foregroundStyle(.black).cornerRadius(14)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // Step 4: Results
    private var captureStep4: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Color.statusGreen)
                Text("Analysis Complete").font(.headline).foregroundStyle(.white)
            }
            Text(isFresh ? "Fresh baseline session recorded successfully." : "Fatigued session — showing delta vs baseline.")
                .font(.caption).foregroundStyle(Color.textSecondary)

            ForEach(captureItems) { item in
                if let m = item.resultMetrics {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name).font(.subheadline.bold()).foregroundStyle(.white)
                        HStack(spacing: 14) {
                            MetricPill(label: "Valgus", value: String(format: "%.1f°", m.valgusAngle), color: .brand)
                            MetricPill(label: "Flexion", value: String(format: "%.1f°", m.kneeFlexionAngle), color: Color(red: 0.3, green: 0.6, blue: 1.0))
                            MetricPill(label: "Asym", value: String(format: "%.0f%%", m.asymmetry), color: .statusYellow)
                            if !isFresh, let a = engine.athletes.first(where: { $0.id == item.id }) {
                                let bl = a.sessions.filter(\.isFresh).map(\.value).reduce(0, +) / max(1, Double(a.sessions.filter(\.isFresh).count))
                                let delta = bl > 0 ? ((m.valgusAngle - bl) / bl) * 100 : 0
                                MetricPill(label: "Delta", value: "+\(Int(delta))%",
                                    color: delta > 18 ? .statusRed : delta > 10 ? .statusYellow : .statusGreen)
                            }
                        }
                    }.padding(14).background(Color.bgCard).cornerRadius(12)
                }
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { step = 1 }
                captureItems = []; selectedAthleteIDs = []; consentGiven = false
            } label: {
                Text("Done").font(.headline)
                    .frame(maxWidth: .infinity).padding(15)
                    .background(Color.brand).foregroundStyle(.black).cornerRadius(14)
            }
        }
    }


    private func startAnalysis() {
        for i in captureItems.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.9) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    captureItems[i].processing = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.9 + 1.4) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    captureItems[i].processing = false
                    captureItems[i].done = true
                }
                let valgus = Double.random(in: 5.5...10.5)
                captureItems[i].resultMetrics = ModelMetrics(
                    valgusAngle: valgus, kneeFlexionAngle: Double.random(in: 48...62),
                    trunkLean: Double.random(in: 3...12), asymmetry: Double.random(in: 2...15),
                    lessScore: Int.random(in: 55...95)
                )
                // Persist session data
                if let idx = engine.athletes.firstIndex(where: { $0.id == captureItems[i].id }) {
                    engine.athletes[idx].sessions.append(
                        DataPoint(date: selectedDate, value: valgus, isFresh: isFresh)
                    )
                    engine.save()
                    // Check for At Risk notification
                    if !isFresh {
                        let r = engine.readiness(for: engine.athletes[idx])
                        if r.status == .atRisk {
                            engine.scheduleAtRiskNotification(name: r.name, degradation: Int(r.fatigueDegradationPct))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Capture Helpers
struct ConditionButton: View {
    let title: String; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold())
                .frame(maxWidth: .infinity).padding(14)
                .background(selected ? Color.brand.opacity(0.15) : Color.bgCard)
                .foregroundStyle(selected ? Color.brand : Color.textSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? Color.brand : Color.bgCardLight, lineWidth: selected ? 2 : 1)
                )
                .cornerRadius(12)
        }
    }
}

struct MetricPill: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundStyle(Color.textSecondary)
            Text(value).font(.caption.bold()).foregroundStyle(color)
        }
    }
}


// MARK: - Roster (with status badges and navigation)
struct RosterView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newJersey = ""
    @State private var newPosition = ""
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if engine.athletes.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "figure.run.circle")
                            .font(.system(size: 52)).foregroundStyle(Color.textSecondary.opacity(0.5))
                        Text("No athletes yet").font(.headline).foregroundStyle(Color.textSecondary)
                        Text("Tap + to add your first athlete").font(.caption).foregroundStyle(Color.textSecondary.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(engine.athletes) { a in
                                let r = engine.readiness(for: a)
                                NavigationLink(value: a.id) {
                                    HStack(spacing: 12) {
                                        JerseyCircle(number: a.jersey, size: 42, glowing: r.status == .atRisk)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(a.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                            Text(a.position).font(.caption).foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer()
                                        StatusBadge(status: r.status)
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(Color.textSecondary.opacity(0.5))
                                    }
                                    .padding(14).background(Color.bgCard).cornerRadius(14)
                                }
                                .buttonStyle(CardPressStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            engine.removeAthlete(a.id)
                                        }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(.horizontal).padding(.top, 8)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                    }
                }
            }
            .navigationTitle("Roster")
            .navigationDestination(for: UUID.self) { id in AthleteDetailView(athleteID: id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(Color.brand)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddAthleteSheet(newName: $newName, newJersey: $newJersey, newPosition: $newPosition) {
                    engine.addAthlete(name: newName, jersey: Int(newJersey) ?? 0, position: newPosition)
                    newName = ""; newJersey = ""; newPosition = ""; showingAdd = false
                } onCancel: { showingAdd = false }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            }
        }
    }
}

struct AddAthleteSheet: View {
    @Binding var newName: String
    @Binding var newJersey: String
    @Binding var newPosition: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 20) {
                    FloatingTextField(label: "Name", placeholder: "e.g. Alex Morgan", text: $newName)
                    FloatingTextField(label: "Jersey #", placeholder: "e.g. 13", text: $newJersey)
                    FloatingTextField(label: "Position", placeholder: "e.g. Forward", text: $newPosition)
                    Spacer()
                }.padding(24).padding(.top, 8)
            }
            .navigationTitle("Add Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }.foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .foregroundStyle(newName.isEmpty ? Color.textSecondary : Color.brand)
                        .disabled(newName.isEmpty)
                }
            }
        }
    }
}


// MARK: - History (Grouped by Date)
struct HistoryView: View {
    @Environment(DataEngine.self) private var engine
    @State private var selectedSession: SessionSheetID? = nil
    @State private var appeared = false

    private var groupedSessions: [(date: Date, isFresh: Bool, count: Int)] {
        var result: [(Date, Bool, Int)] = []
        var seen: Set<String> = []
        for athlete in engine.athletes {
            for s in athlete.sessions {
                let key = "\(Int(s.date.timeIntervalSince1970 / 86400))-\(s.isFresh)"
                if !seen.contains(key) {
                    seen.insert(key)
                    let count = engine.athletes.filter { a in
                        a.sessions.contains { abs($0.date.timeIntervalSince(s.date)) < 86400 && $0.isFresh == s.isFresh }
                    }.count
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
                    VStack(spacing: 14) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 48)).foregroundStyle(Color.textSecondary.opacity(0.5))
                        Text("No sessions yet").font(.headline).foregroundStyle(Color.textSecondary)
                        Text("Capture a session to see history here").font(.caption).foregroundStyle(Color.textSecondary.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(groupedSessions.enumerated()), id: \.offset) { idx, session in
                                Button {
                                    selectedSession = SessionSheetID(date: session.date, isFresh: session.isFresh)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(session.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                                .font(.subheadline.bold()).foregroundStyle(.white)
                                            Text("\(session.count) athlete\(session.count > 1 ? "s" : "")")
                                                .font(.caption).foregroundStyle(Color.textSecondary)
                                        }
                                        Spacer()
                                        Text(session.isFresh ? "Fresh" : "Fatigued")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(session.isFresh ? Color.statusGreen.opacity(0.15) : Color.statusYellow.opacity(0.15))
                                            .foregroundStyle(session.isFresh ? Color.statusGreen : Color.statusYellow)
                                            .clipShape(Capsule())
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundStyle(Color.textSecondary.opacity(0.4))
                                    }.padding(14).background(Color.bgCard).cornerRadius(12)
                                }.buttonStyle(CardPressStyle())
                            }
                        }
                        .padding(.horizontal).padding(.top, 8)
                        .opacity(appeared ? 1 : 0)
                    }
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedSession) { item in
                SessionDetailSheet(date: item.date, isFresh: item.isFresh)
            }
            .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
        }
    }
}

struct SessionSheetID: Identifiable {
    let date: Date; let isFresh: Bool
    var id: String { "\(Int(date.timeIntervalSince1970 / 86400))-\(isFresh)" }
}


// MARK: - Session Detail Sheet (Color-coded values)
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
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: isFresh ? "leaf.fill" : "flame.fill")
                                .foregroundStyle(isFresh ? Color.statusGreen : Color.statusYellow)
                            Text(isFresh ? "Fresh Session" : "Fatigued Session")
                                .font(.headline).foregroundStyle(.white)
                        }
                        Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.subheadline).foregroundStyle(Color.textSecondary)

                        Divider().background(Color.bgCardLight)

                        ForEach(engine.athletes) { a in
                            if let s = a.sessions.first(where: {
                                abs($0.date.timeIntervalSince(date)) < 86400 && $0.isFresh == isFresh
                            }) {
                                HStack(spacing: 12) {
                                    JerseyCircle(number: a.jersey, size: 34)
                                    Text(a.name).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.1f°", s.value))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(isFresh ? .white : valgusColor(for: a, value: s.value))
                                }
                                .padding(12).background(Color.bgCard).cornerRadius(10)
                            }
                        }
                    }.padding(20)
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Settings (Complete)
struct SettingsView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showResetConfirm = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Team Section
                        SettingsSection(title: "TEAM") {
                            SettingsRow(icon: "person.3.fill", label: "Team Name") {
                                TextField("", text: Binding(
                                    get: { engine.teamName },
                                    set: { engine.teamName = $0; engine.storedTeamName = $0 }
                                ))
                                .multilineTextAlignment(.trailing).foregroundStyle(Color.brand)
                            }
                            SettingsRow(icon: "person.fill", label: "Coach") {
                                TextField("", text: Binding(
                                    get: { engine.userName },
                                    set: { engine.userName = $0; engine.storedCoachName = $0 }
                                ))
                                .multilineTextAlignment(.trailing).foregroundStyle(Color.brand)
                            }
                            SettingsRow(icon: "sportscourt.fill", label: "Sport") {
                                Text(engine.sportType).foregroundStyle(Color.textSecondary)
                            }
                        }

                        // Risk Thresholds
                        SettingsSection(title: "RISK THRESHOLDS") {
                            SettingsRow(icon: "exclamationmark.triangle", label: "Caution at") {
                                HStack(spacing: 4) {
                                    TextField("", value: Binding(
                                        get: { engine.cautionThreshold },
                                        set: { engine.cautionThreshold = $0 }
                                    ), format: .number)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                    .frame(width: 50).foregroundStyle(Color.statusYellow)
                                    Text("%").foregroundStyle(Color.textSecondary)
                                }
                            }
                            SettingsRow(icon: "xmark.octagon", label: "At Risk at") {
                                HStack(spacing: 4) {
                                    TextField("", value: Binding(
                                        get: { engine.atRiskThreshold },
                                        set: { engine.atRiskThreshold = $0 }
                                    ), format: .number)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                    .frame(width: 50).foregroundStyle(Color.statusRed)
                                    Text("%").foregroundStyle(Color.textSecondary)
                                }
                            }
                        }

                        // Notifications
                        SettingsSection(title: "NOTIFICATIONS") {
                            HStack {
                                Image(systemName: "bell.badge.fill").foregroundStyle(Color.brand).frame(width: 24)
                                Text("Risk Alerts").foregroundStyle(.white)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { engine.notificationsEnabled },
                                    set: { val in
                                        if val { engine.requestNotificationPermission() }
                                        else { engine.notificationsEnabled = false }
                                    }
                                )).labelsHidden().tint(Color.brand)
                            }.padding(14)
                        }

                        // About
                        SettingsSection(title: "ABOUT") {
                            SettingsRow(icon: "info.circle", label: "Version") {
                                Text("3.0.0").foregroundStyle(Color.textSecondary)
                            }
                            SettingsRow(icon: "hammer", label: "Build") {
                                Text("2025.07").foregroundStyle(Color.textSecondary)
                            }
                        }

                        // Actions
                        VStack(spacing: 10) {
                            Button {
                                showResetConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset Demo Data")
                                }
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.bgCard).foregroundStyle(Color.statusYellow)
                                .cornerRadius(12)
                            }
                            Button {
                                showSignOutConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                                    Text("Sign Out")
                                }
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.bgCard).foregroundStyle(Color.statusRed)
                                .cornerRadius(12)
                            }
                        }.padding(.horizontal)
                    }.padding(.vertical)
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Demo Data?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { engine.resetDemo() }
            } message: { Text("This will replace all data with fresh demo athletes and sessions.") }
            .alert("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    engine.isSignedIn = false
                    engine.hasCompletedOnboarding = false
                }
            } message: { Text("You'll need to sign in again to access your data.") }
        }
    }
}


// MARK: - Settings Helpers
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .tracking(1.2)
                .padding(.horizontal).padding(.bottom, 8)
            VStack(spacing: 1) { content }
                .background(Color.bgCard)
                .cornerRadius(14)
                .padding(.horizontal)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let icon: String; let label: String
    @ViewBuilder let accessory: Accessory
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.brand).frame(width: 24)
            Text(label).foregroundStyle(.white)
            Spacer()
            accessory
        }
        .padding(14)
    }
}
