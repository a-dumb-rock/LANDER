import SwiftUI
import Foundation

// MARK: - Models

enum ReadinessStatus: String, CaseIterable {
    case green = "Green"
    case yellow = "Yellow"
    case red = "Red"

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

enum TrendDirection: String {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
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

    init() {
        seedDemoData()
    }

    func seedDemoData() {
        let demoAthletes = [
            Athlete(id: UUID(), name: "Maya Johnson", jerseyNumber: 7, position: "Forward"),
            Athlete(id: UUID(), name: "Carlos Rivera", jerseyNumber: 12, position: "Midfielder"),
            Athlete(id: UUID(), name: "Aisha Patel", jerseyNumber: 3, position: "Defender"),
            Athlete(id: UUID(), name: "Jake Thompson", jerseyNumber: 21, position: "Goalkeeper")
        ]
        athletes = demoAthletes

        let calendar = Calendar.current
        let today = Date()
        var allSessions: [CaptureSession] = []


        for weekOffset in (0..<4).reversed() {
            for dayOffset in [0, 3] {
                let date = calendar.date(byAdding: .day, value: -(weekOffset * 7 + dayOffset), to: today)!
                let isFresh = dayOffset == 0
                var metrics: [UUID: ModelMetrics] = [:]
                for (index, athlete) in demoAthletes.enumerated() {
                    let fatigueFactor = isFresh ? 0.0 : Double(weekOffset) * 0.5 + Double(index) * 0.3
                    metrics[athlete.id] = generateMetrics(fatigueFactor: fatigueFactor, athleteIndex: index)
                }
                let session = CaptureSession(
                    id: UUID(),
                    date: date,
                    isFresh: isFresh,
                    athleteIDs: demoAthletes.map { $0.id },
                    metrics: metrics
                )
                allSessions.append(session)
            }
        }
        sessions = allSessions.sorted { $0.date < $1.date }
    }

    private func generateMetrics(fatigueFactor: Double, athleteIndex: Int) -> ModelMetrics {
        let base = 45.0 + Double(athleteIndex) * 3
        let jitter = Double.random(in: -2...2)
        return ModelMetrics(
            kneeFlexionAngle: base - fatigueFactor * 2 + jitter,
            valgusAngle: 5.0 + fatigueFactor * 1.5 + Double.random(in: -1...1),
            landingForce: 2.5 + fatigueFactor * 0.3 + Double.random(in: -0.2...0.2),
            stabilizationTime: 0.6 + fatigueFactor * 0.1 + Double.random(in: -0.05...0.05),
            symmetryIndex: 92.0 - fatigueFactor * 2 + Double.random(in: -1...1)
        )
    }


    func computeReadiness() -> [AthleteReadiness] {
        return athletes.map { athlete in
            let athleteSessions = sessions.filter { $0.athleteIDs.contains(athlete.id) }
            let freshSessions = athleteSessions.filter { $0.isFresh }
            let fatiguedSessions = athleteSessions.filter { !$0.isFresh }

            let freshScores = freshSessions.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let fatiguedScores = fatiguedSessions.compactMap { $0.metrics[athlete.id]?.compositeScore }

            let baseline = freshScores.isEmpty ? 80.0 : freshScores.reduce(0, +) / Double(freshScores.count)
            let current = fatiguedScores.last ?? baseline
            let delta = baseline - current

            let status: ReadinessStatus
            if delta >= thresholds.redDelta {
                status = .red
            } else if delta >= thresholds.yellowDelta {
                status = .yellow
            } else {
                status = .green
            }

            let allScores = athleteSessions.compactMap { $0.metrics[athlete.id]?.compositeScore }
            let trend: TrendDirection
            if allScores.count >= 3 {
                let recent = Array(allScores.suffix(3))
                let diff = recent.last! - recent.first!
                if diff > 2 { trend = .improving }
                else if diff < -2 { trend = .declining }
                else { trend = .stable }
            } else {
                trend = .stable
            }

            return AthleteReadiness(
                id: athlete.id,
                athlete: athlete,
                currentScore: current,
                baselineScore: baseline,
                delta: delta,
                status: status,
                trend: trend,
                history: allScores
            )
        }
    }


    func addAthlete(name: String, jerseyNumber: Int, position: String) {
        let athlete = Athlete(id: UUID(), name: name, jerseyNumber: jerseyNumber, position: position)
        athletes.append(athlete)
    }

    func removeAthlete(id: UUID) {
        athletes.removeAll { $0.id == id }
    }

    func runCapture(date: Date, isFresh: Bool, athleteIDs: [UUID]) {
        var metrics: [UUID: ModelMetrics] = [:]
        for (index, id) in athleteIDs.enumerated() {
            let fatigue = isFresh ? 0.0 : Double.random(in: 1...4)
            metrics[id] = generateMetrics(fatigueFactor: fatigue, athleteIndex: index)
        }
        let session = CaptureSession(id: UUID(), date: date, isFresh: isFresh, athleteIDs: athleteIDs, metrics: metrics)
        sessions.append(session)
        sessions.sort { $0.date < $1.date }
    }
}

// MARK: - Brand Colors

extension Color {
    static let brand = Color(red: 14/255, green: 165/255, blue: 233/255)
}


// MARK: - App Entry Point

@main
struct BuddyAppApp: App {
    @State private var engine = DataEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
        }
    }
}

// MARK: - Content View (Tab Bar)

struct ContentView: View {
    var body: some View {
        TabView {
            ReadinessBoardView()
                .tabItem { Label("Readiness", systemImage: "heart.text.clipboard") }
            CaptureFlowView()
                .tabItem { Label("Capture", systemImage: "camera.fill") }
            RosterView()
                .tabItem { Label("Roster", systemImage: "person.3.fill") }
            SessionsListView()
                .tabItem { Label("Sessions", systemImage: "list.bullet.clipboard") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.brand)
    }
}


// MARK: - Readiness Board View

struct ReadinessBoardView: View {
    @Environment(DataEngine.self) private var engine

    var body: some View {
        NavigationStack {
            List {
                let readiness = engine.computeReadiness()
                ForEach(readiness) { item in
                    NavigationLink(destination: AthleteDetailView(athleteID: item.athlete.id)) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(item.status.color)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("#\(item.athlete.jerseyNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.athlete.name)
                                        .font(.headline)
                                }
                                Text(item.athlete.position)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f%%", item.delta))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(item.status.color)
                                HStack(spacing: 2) {
                                    Image(systemName: item.trend.icon)
                                        .font(.caption2)
                                    Text(item.trend.rawValue)
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Readiness Board")
        }
    }
}


// MARK: - Athlete Detail View

struct AthleteDetailView: View {
    @Environment(DataEngine.self) private var engine
    let athleteID: UUID

    var body: some View {
        let readinessItems = engine.computeReadiness()
        if let item = readinessItems.first(where: { $0.id == athleteID }) {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Header
                    VStack(spacing: 8) {
                        Circle()
                            .fill(item.status.color)
                            .frame(width: 40, height: 40)
                        Text(item.status.rawValue)
                            .font(.title2.bold())
                        Text(String(format: "Delta: %.1f%%", item.delta))
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    // Mini Chart
                    MiniChartView(data: item.history)
                        .frame(height: 120)
                        .padding(.horizontal)

                    // Stats
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Baseline", value: String(format: "%.1f", item.baselineScore))
                        StatCard(title: "Current", value: String(format: "%.1f", item.currentScore))
                        StatCard(title: "Trend", value: item.trend.rawValue)
                        StatCard(title: "Sessions", value: "\(engine.sessions.filter { $0.athleteIDs.contains(athleteID) }.count)")
                    }
                    .padding(.horizontal)

                    // Session History
                    VStack(alignment: .leading) {
                        Text("Recent Sessions")
                            .font(.headline)
                            .padding(.horizontal)
                        let athleteSessions = engine.sessions
                            .filter { $0.athleteIDs.contains(athleteID) }
                            .sorted { $0.date > $1.date }
                            .prefix(5)
                        ForEach(Array(athleteSessions)) { session in
                            if let m = session.metrics[athleteID] {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.date, style: .date)
                                            .font(.subheadline)
                                        Text(session.isFresh ? "Fresh" : "Fatigued")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f", m.compositeScore))
                                        .font(.subheadline.monospacedDigit())
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(item.athlete.name)
        } else {
            Text("Athlete not found")
        }
    }
}


// MARK: - Mini Chart View

struct MiniChartView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            if data.count > 1 {
                let minVal = (data.min() ?? 0) - 5
                let maxVal = (data.max() ?? 100) + 5
                let range = maxVal - minVal
                let stepX = geo.size.width / CGFloat(data.count - 1)

                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geo.size.height - (CGFloat((value - minVal) / range) * geo.size.height)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.brand, lineWidth: 2)
            } else {
                Text("Not enough data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


// MARK: - Capture Flow View

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
                Section("Session Info") {
                    DatePicker("Date", selection: $captureDate, displayedComponents: .date)
                    Picker("Condition", selection: $isFresh) {
                        Text("Fresh (Baseline)").tag(true)
                        Text("Fatigued (Post-Practice)").tag(false)
                    }
                }

                Section("Select Athletes") {
                    ForEach(engine.athletes) { athlete in
                        Button {
                            if selectedAthletes.contains(athlete.id) {
                                selectedAthletes.remove(athlete.id)
                            } else {
                                selectedAthletes.insert(athlete.id)
                            }
                        } label: {
                            HStack {
                                Text("#\(athlete.jerseyNumber) \(athlete.name)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedAthletes.contains(athlete.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.brand)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        processCapture()
                    } label: {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Processing...")
                            } else {
                                Image(systemName: "play.fill")
                                Text("Run Capture")
                            }
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .disabled(selectedAthletes.isEmpty || isProcessing)
                }
            }
            .navigationTitle("New Capture")
            .alert("Capture Complete", isPresented: $showComplete) {
                Button("OK") {
                    selectedAthletes.removeAll()
                }
            } message: {
                Text("Successfully processed \(selectedAthletes.count) athlete(s).")
            }
        }
    }

    private func processCapture() {
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            engine.runCapture(date: captureDate, isFresh: isFresh, athleteIDs: Array(selectedAthletes))
            isProcessing = false
            showComplete = true
        }
    }
}


// MARK: - Roster View

struct RosterView: View {
    @Environment(DataEngine.self) private var engine
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newJersey = ""
    @State private var newPosition = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(engine.athletes) { athlete in
                    HStack {
                        Text("#\(athlete.jerseyNumber)")
                            .font(.headline)
                            .foregroundStyle(.brand)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text(athlete.name)
                                .font(.body)
                            Text(athlete.position)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        engine.removeAthlete(id: engine.athletes[index].id)
                    }
                }
            }
            .navigationTitle("Roster")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $newName)
                        TextField("Jersey Number", text: $newJersey)
                            .keyboardType(.numberPad)
                        TextField("Position", text: $newPosition)
                    }
                    .navigationTitle("Add Athlete")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAddSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                if let num = Int(newJersey), !newName.isEmpty {
                                    engine.addAthlete(name: newName, jerseyNumber: num, position: newPosition)
                                    newName = ""
                                    newJersey = ""
                                    newPosition = ""
                                    showAddSheet = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Sessions List View

struct SessionsListView: View {
    @Environment(DataEngine.self) private var engine

    var body: some View {
        NavigationStack {
            List {
                let sorted = engine.sessions.sorted { $0.date > $1.date }
                ForEach(sorted) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.date, style: .date)
                                .font(.headline)
                            Spacer()
                            Text(session.isFresh ? "Fresh" : "Fatigued")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(session.isFresh ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        Text("\(session.athleteIDs.count) athlete(s)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Sessions")
        }
    }
}


// MARK: - Settings View

struct SettingsView: View {
    @Environment(DataEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine
        NavigationStack {
            Form {
                Section("Readiness Thresholds") {
                    HStack {
                        Text("Yellow Alert (% delta)")
                        Spacer()
                        TextField("", value: $engine.thresholds.yellowDelta, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                    }
                    HStack {
                        Text("Red Alert (% delta)")
                        Spacer()
                        TextField("", value: $engine.thresholds.redDelta, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Engine")
                        Spacer()
                        Text("LANDER Delta v1")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    Button("Reset Demo Data") {
                        engine.seedDemoData()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
