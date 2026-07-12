import SwiftUI
import PhotosUI

struct CaptureSessionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    
    @State private var sessionDate = Date()
    @State private var sessionState: SessionState = .fresh
    @State private var items: [CaptureItem] = []
    @State private var step: CaptureStep = .setup
    @State private var error: String?
    @State private var showingPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    enum CaptureStep {
        case setup, upload, processing, summary
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Step indicator
                    StepIndicator(current: step)
                        .padding(.horizontal)
                    
                    switch step {
                    case .setup:
                        setupView
                    case .upload:
                        uploadView
                    case .processing:
                        processingView
                    case .summary:
                        summaryView
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("New Capture")
        }
    }
    
    // MARK: - Step 1: Setup
    
    private var setupView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Date")
                    .font(.subheadline.weight(.medium))
                DatePicker("", selection: $sessionDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Type")
                    .font(.subheadline.weight(.medium))
                Picker("Type", selection: $sessionState) {
                    ForEach(SessionState.allCases, id: \.self) { state in
                        Text(state.label).tag(state)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            TipCard()
            
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Button("Next: Upload Videos") {
                if appState.athletes.isEmpty {
                    self.error = "Add athletes to your roster first."
                } else {
                    step = .upload
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Step 2: Upload
    
    private var uploadView: some View {
        VStack(spacing: 16) {
            Text("Upload one video per athlete and assign each.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Video picker
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 20,
                matching: .videos
            ) {
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.plus")
                        .font(.largeTitle)
                        .foregroundColor(.brand)
                    Text("Select Videos")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.brand)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.brand.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.brand.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
            }
            .onChange(of: selectedPhotos) { _, newItems in
                for item in newItems {
                    let captureItem = CaptureItem(
                        athleteId: appState.athletes.first?.id,
                        athleteName: appState.athletes.first?.name ?? ""
                    )
                    items.append(captureItem)
                }
                selectedPhotos = []
            }
            
            // Items list
            if !items.isEmpty {
                ForEach(items.indices, id: \.self) { index in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Video \(index + 1)")
                                .font(.subheadline.weight(.medium))
                        }
                        
                        Spacer()
                        
                        Picker("Athlete", selection: Binding(
                            get: { items[index].athleteId ?? appState.athletes.first?.id ?? UUID() },
                            set: { newId in
                                items[index].athleteId = newId
                                items[index].athleteName = appState.athletes.first(where: { $0.id == newId })?.name ?? ""
                            }
                        )) {
                            ForEach(appState.athletes) { athlete in
                                Text("#\(athlete.jerseyNumber) \(athlete.name)")
                                    .tag(athlete.id)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Button(role: .destructive) {
                            items.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red.opacity(0.6))
                        }
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            HStack {
                Button("Back") { step = .setup }
                    .buttonStyle(.bordered)
                
                Button("Submit & Analyze (\(items.count))") {
                    Task { await processCaptures() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .disabled(items.isEmpty)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Step 3: Processing
    
    private var processingView: some View {
        VStack(spacing: 16) {
            Text("Analyzing with LANDER CV model...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    Text(items[index].athleteName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    switch items[index].status {
                    case .pending:
                        Text("Waiting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .processing:
                        ProgressView()
                            .controlSize(.small)
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.statusGreen)
                    case .error:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.statusRed)
                    }
                }
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Step 4: Summary
    
    private var summaryView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.statusGreen)
                Text("Session Complete!")
                    .font(.headline)
                Text("\(sessionState.shortLabel) session — \(items.filter { $0.status == .done }.count)/\(items.count) processed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ForEach(items.indices, id: \.self) { index in
                if let metrics = items[index].metrics {
                    HStack {
                        Text(items[index].athleteName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Valgus: \(String(format: "%.1f", metrics.kneeValgusDeg))°")
                                .font(.caption)
                            Text("Flexion: \(String(format: "%.1f", metrics.kneeFlexionDeg))°")
                                .font(.caption)
                        }
                        StatusBadge(status: riskToStatus(metrics.riskLevel))
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            Button("Back to Readiness Board") {
                items = []
                step = .setup
                Task { await appState.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Process
    
    private func processCaptures() async {
        step = .processing
        
        guard let teamId = appState.team?.id,
              let userId = authManager.userId else { return }
        
        // Create session in DB
        do {
            let session = try await SupabaseManager.shared.createSession(
                teamId: teamId,
                date: sessionDate,
                state: sessionState,
                userId: userId
            )
            
            for i in items.indices {
                items[i].status = .processing
                
                do {
                    let metrics = try await CVModelService.analyzeVideo(
                        videoURL: items[i].videoURL ?? URL(string: "mock://video")!,
                        sessionState: sessionState
                    )
                    
                    try await SupabaseManager.shared.insertCapture(
                        sessionId: session.id,
                        athleteId: items[i].athleteId ?? UUID(),
                        metrics: metrics
                    )
                    
                    items[i].metrics = metrics
                    items[i].status = .done
                } catch {
                    items[i].error = error.localizedDescription
                    items[i].status = .error
                }
            }
        } catch {
            self.error = error.localizedDescription
            step = .upload
            return
        }
        
        step = .summary
    }
    
    private func riskToStatus(_ risk: String) -> ReadinessStatus {
        if risk.contains("HIGH") { return .red }
        if risk.contains("MODERATE") { return .yellow }
        if risk.contains("LOW") { return .green }
        return .none
    }
}

// MARK: - Step Indicator

struct StepIndicator: View {
    let current: CaptureSessionView.CaptureStep
    
    private let steps: [CaptureSessionView.CaptureStep] = [.setup, .upload, .processing, .summary]
    private let labels = ["Setup", "Upload", "Process", "Done"]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { i in
                let isActive = steps.firstIndex(of: current)! >= i
                HStack(spacing: 4) {
                    Circle()
                        .fill(isActive ? Color.brand : Color(.systemGray4))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("\(i + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(isActive ? .white : .secondary)
                        )
                    Text(labels[i])
                        .font(.caption2)
                        .foregroundColor(isActive ? .primary : .secondary)
                }
                if i < steps.count - 1 {
                    Rectangle()
                        .fill(isActive ? Color.brand.opacity(0.3) : Color(.systemGray5))
                        .frame(height: 2)
                }
            }
        }
    }
}

extension CaptureSessionView.CaptureStep: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.setup, .upload, .processing, .summary]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}
