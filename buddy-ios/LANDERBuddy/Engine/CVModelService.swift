import Foundation

/// CV Model integration — mock mode only (no server needed).
enum CVModelService {
    
    static func analyzeVideo(videoURL: URL, sessionState: SessionState) async throws -> ModelMetrics {
        return await mockAnalyze(sessionState: sessionState)
    }
    
    /// Synchronous version for seeding demo data
    static func mockMetricsSync(sessionState: SessionState) -> ModelMetrics {
        let isFatigued = sessionState == .fatigued
        
        let valgus = max(0, gaussianRandom(mean: isFatigued ? 9.5 : 5.5, std: 2.5))
        let flexion = max(15, gaussianRandom(mean: isFatigued ? 33 : 44, std: 6))
        let trunk = max(0, gaussianRandom(mean: 18, std: 5))
        let asymmetry = max(0, gaussianRandom(mean: 0.06, std: 0.03))
        let less = max(0, Double(Int(gaussianRandom(mean: isFatigued ? 6 : 3, std: 1.5))))
        
        let riskLevel: String
        if valgus > 10 || flexion < 30 {
            riskLevel = "HIGH RISK"
        } else if valgus > 5 || flexion < 45 {
            riskLevel = "MODERATE RISK"
        } else {
            riskLevel = "LOW RISK"
        }
        
        return ModelMetrics(
            kneeValgusDeg: round(valgus * 100) / 100,
            kneeFlexionDeg: round(flexion * 100) / 100,
            trunkLeanDeg: round(trunk * 100) / 100,
            lessScore: less,
            riskLevel: riskLevel,
            asymmetryIndex: round(asymmetry * 10000) / 10000
        )
    }
    
    private static func mockAnalyze(sessionState: SessionState) async -> ModelMetrics {
        try? await Task.sleep(nanoseconds: UInt64((0.6 + Double.random(in: 0...0.8)) * 1_000_000_000))
        return mockMetricsSync(sessionState: sessionState)
    }
    
    private static func gaussianRandom(mean: Double, std: Double) -> Double {
        let u1 = Double.random(in: 0.001...1)
        let u2 = Double.random(in: 0.001...1)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return mean + std * z
    }
}
