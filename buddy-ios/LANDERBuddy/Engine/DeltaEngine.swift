import Foundation

/// The core product logic — computes baselines, fatigue deltas, trends, and readiness.
/// This is the heart of LANDER Buddy. A single measurement is NOT the product;
/// CHANGE OVER TIME (within-athlete deltas) is the product.
enum DeltaEngine {
    
    // MARK: - Baseline
    
    struct Baseline {
        var valgus: Double?
        var flexion: Double?
        var lessScore: Double?
        var n: Int
    }
    
    /// Compute a rolling baseline from the last N fresh captures for an athlete.
    static func computeBaseline(freshCaptures: [Capture], n: Int = 3) -> Baseline {
        let sorted = freshCaptures
            .filter { $0.kneeValgusDeg != nil || $0.kneeFlexionDeg != nil }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(n)
        
        let valgusValues = sorted.compactMap { $0.kneeValgusDeg }
        let flexionValues = sorted.compactMap { $0.kneeFlexionDeg }
        let lessValues = sorted.compactMap { $0.lessScore }
        
        return Baseline(
            valgus: valgusValues.isEmpty ? nil : valgusValues.reduce(0, +) / Double(valgusValues.count),
            flexion: flexionValues.isEmpty ? nil : flexionValues.reduce(0, +) / Double(flexionValues.count),
            lessScore: lessValues.isEmpty ? nil : lessValues.reduce(0, +) / Double(lessValues.count),
            n: Array(sorted).count
        )
    }
    
    // MARK: - Fatigue Delta
    
    struct FatigueDelta {
        var valgusDeltaDeg: Double?
        var flexionDeltaDeg: Double?
        var valgusDeltaPct: Double?
        var flexionDeltaPct: Double?
        var lessScoreDelta: Double?
        var vulnerabilityScore: Double?
    }
    
    /// Compute the fatigue delta for a single fatigued capture vs the baseline.
    static func computeFatigueDelta(fatiguedCapture: Capture, baseline: Baseline) -> FatigueDelta {
        let valgusDelta: Double? = {
            guard let v = fatiguedCapture.kneeValgusDeg, let bv = baseline.valgus else { return nil }
            return v - bv
        }()
        
        let flexionDelta: Double? = {
            guard let f = fatiguedCapture.kneeFlexionDeg, let bf = baseline.flexion else { return nil }
            return f - bf
        }()
        
        let lessDelta: Double? = {
            guard let l = fatiguedCapture.lessScore, let bl = baseline.lessScore else { return nil }
            return l - bl
        }()
        
        let valgusPct: Double? = {
            guard let vd = valgusDelta, let bv = baseline.valgus, bv != 0 else { return nil }
            return (vd / abs(bv)) * 100
        }()
        
        let flexionPct: Double? = {
            guard let fd = flexionDelta, let bf = baseline.flexion, bf != 0 else { return nil }
            return (fd / abs(bf)) * 100
        }()
        
        return FatigueDelta(
            valgusDeltaDeg: valgusDelta.map { round($0 * 100) / 100 },
            flexionDeltaDeg: flexionDelta.map { round($0 * 100) / 100 },
            valgusDeltaPct: valgusPct.map { round($0 * 10) / 10 },
            flexionDeltaPct: flexionPct.map { round($0 * 10) / 10 },
            lessScoreDelta: lessDelta.map { round($0 * 10) / 10 },
            vulnerabilityScore: fatiguedCapture.vulnerabilityScore
        )
    }
    
    // MARK: - Trend
    
    /// Look at the last 4 fatigue deltas and determine if things are improving, stable, or worsening.
    /// Uses simple linear regression slope on valgus delta over time.
    static func computeTrend(deltas: [(date: Date, valgusDelta: Double)]) -> TrendDirection {
        let valid = deltas
            .sorted { $0.date < $1.date }
            .suffix(4)
        
        guard valid.count >= 2 else { return .unknown }
        
        let n = Double(valid.count)
        let xs = valid.enumerated().map { Double($0.offset) }
        let ys = valid.map { $0.valgusDelta }
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        
        let num = zip(xs, ys).reduce(0.0) { $0 + ($1.0 - xMean) * ($1.1 - yMean) }
        let den = xs.reduce(0.0) { $0 + ($1 - xMean) * ($1 - xMean) }
        let slope = den == 0 ? 0 : num / den
        
        if slope > 0.5 { return .worsening }
        if slope < -0.5 { return .improving }
        return .stable
    }
    
    // MARK: - Readiness Status
    
    /// Green / Yellow / Red derivation from absolute metrics + fatigue delta + trend.
    static func computeReadinessStatus(
        latestFresh: Capture?,
        latestFatigued: Capture?,
        baseline: Baseline,
        trend: TrendDirection,
        thresholds: Thresholds
    ) -> ReadinessStatus {
        guard latestFresh != nil || latestFatigued != nil else { return .none }
        
        let capture = latestFatigued ?? latestFresh!
        let valgus = capture.kneeValgusDeg ?? 0
        let flexion = capture.kneeFlexionDeg ?? 999
        
        // Absolute risk from raw metrics
        if valgus >= thresholds.valgusRedDeg || flexion <= thresholds.flexionRedDeg {
            return .red
        }
        
        // Fatigue delta risk
        if let fatigued = latestFatigued, baseline.valgus != nil {
            let delta = computeFatigueDelta(fatiguedCapture: fatigued, baseline: baseline)
            if let pct = delta.valgusDeltaPct {
                if pct >= thresholds.deltaRedPct { return .red }
                if pct >= thresholds.deltaYellowPct { return .yellow }
            }
        }
        
        // Trend contribution
        if trend == .worsening { return .yellow }
        
        // Caution zone absolute metrics
        if valgus >= thresholds.valgusYellowDeg || flexion <= thresholds.flexionYellowDeg {
            return .yellow
        }
        
        return .green
    }
    
    // MARK: - Recommendation
    
    static func generateRecommendation(
        status: ReadinessStatus,
        trend: TrendDirection,
        delta: FatigueDelta?,
        thresholds: Thresholds
    ) -> String {
        switch status {
        case .none:
            return "No data yet — run a fresh capture session."
            
        case .red:
            if let pct = delta?.valgusDeltaPct, pct >= thresholds.deltaRedPct {
                return "High risk — recommend rest. Landing degraded \(Int(pct))% under fatigue vs. baseline."
            }
            return "High risk — recommend rest or reduced load. High valgus or stiff landing detected."
            
        case .yellow:
            if trend == .worsening {
                return "Trending toward risk over the last few weeks — monitor closely and consider load reduction."
            }
            if let pct = delta?.valgusDeltaPct {
                return "Caution — watch training load. Fatigue degradation: \(Int(pct))% above baseline."
            }
            return "Caution — mechanics in caution zone. Watch training load this week."
            
        case .green:
            if trend == .improving {
                return "Stable and improving — keep current training plan."
            }
            return "Looking good — mechanics stable within baseline."
        }
    }
    
    // MARK: - Full Readiness for One Athlete
    
    static func computeAthleteReadiness(
        athlete: Athlete,
        sessions: [CaptureSession],
        captures: [Capture],
        thresholds: Thresholds
    ) -> AthleteReadiness {
        // Filter captures for this athlete
        let athleteCaptures = captures.filter { $0.athleteId == athlete.id }
        
        // Split by session state
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        
        let freshCaptures = athleteCaptures.filter { cap in
            sessionMap[cap.sessionId]?.state == .fresh
        }
        let fatiguedCaptures = athleteCaptures.filter { cap in
            sessionMap[cap.sessionId]?.state == .fatigued
        }
        
        let baseline = computeBaseline(freshCaptures: freshCaptures, n: thresholds.baselineNSessions)
        
        // Latest readings
        let latestFresh = freshCaptures.sorted { $0.createdAt > $1.createdAt }.first
        let latestFatigued = fatiguedCaptures.sorted { $0.createdAt > $1.createdAt }.first
        
        // Trend points
        let trendPoints: [(date: Date, valgusDelta: Double)] = fatiguedCaptures.compactMap { cap in
            guard let v = cap.kneeValgusDeg, let bv = baseline.valgus else { return nil }
            return (cap.createdAt, v - bv)
        }
        
        let trend = computeTrend(deltas: trendPoints)
        let delta = latestFatigued.map { computeFatigueDelta(fatiguedCapture: $0, baseline: baseline) }
        
        let status = computeReadinessStatus(
            latestFresh: latestFresh,
            latestFatigued: latestFatigued,
            baseline: baseline,
            trend: trend,
            thresholds: thresholds
        )
        
        let recommendation = generateRecommendation(status: status, trend: trend, delta: delta, thresholds: thresholds)
        
        // Build note
        var note = recommendation
        if let pct = delta?.valgusDeltaPct {
            note = "↑\(Int(pct))% under fatigue"
            if trend == .worsening { note += " · trending ↑" }
            else if trend == .improving { note += " · trending ↓" }
        } else if status == .none {
            note = "No data"
        } else if status == .green {
            note = "Stable"
        }
        
        // Weeks of data
        let weekSet = Set(athleteCaptures.compactMap { cap -> Int? in
            guard let session = sessionMap[cap.sessionId] else { return nil }
            return Calendar.current.component(.weekOfYear, from: session.date)
        })
        
        let latestCapture = latestFatigued ?? latestFresh
        
        return AthleteReadiness(
            athlete: athlete,
            status: status,
            trend: trend,
            latestValgus: latestCapture?.kneeValgusDeg,
            latestFlexion: latestCapture?.kneeFlexionDeg,
            fatigueDeltaPct: delta?.valgusDeltaPct,
            vulnerabilityScore: delta?.vulnerabilityScore ?? latestFatigued?.vulnerabilityScore,
            note: note,
            hasBaseline: baseline.n >= 1,
            weeksOfData: weekSet.count,
            recommendation: recommendation
        )
    }
    
    // MARK: - Full Team Readiness
    
    static func computeTeamReadiness(
        athletes: [Athlete],
        sessions: [CaptureSession],
        captures: [Capture],
        thresholds: Thresholds
    ) -> [AthleteReadiness] {
        let list = athletes.map { athlete in
            computeAthleteReadiness(
                athlete: athlete,
                sessions: sessions,
                captures: captures,
                thresholds: thresholds
            )
        }
        
        // Sort: red first, then yellow, then green, then none
        let order: [ReadinessStatus: Int] = [.red: 0, .yellow: 1, .green: 2, .none: 3]
        return list.sorted { (order[$0.status] ?? 4) < (order[$1.status] ?? 4) }
    }
}
