import Foundation

/// CV Model integration — sends a video to LANDER backend, returns metrics.
/// Falls back to a realistic mock when Config.useMockModel is true.
enum CVModelService {
    
    // MARK: - Public API
    
    static func analyzeVideo(videoURL: URL, sessionState: SessionState) async throws -> ModelMetrics {
        if Config.useMockModel {
            return await mockAnalyze(sessionState: sessionState)
        } else {
            return try await realAnalyze(videoURL: videoURL)
        }
    }
    
    // MARK: - Mock (realistic biomechanics values)
    
    private static func mockAnalyze(sessionState: SessionState) async -> ModelMetrics {
        // Simulate processing time (600ms–1.4s)
        try? await Task.sleep(nanoseconds: UInt64((0.6 + Double.random(in: 0...0.8)) * 1_000_000_000))
        
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
    
    // MARK: - Real API call
    
    private static func realAnalyze(videoURL: URL) async throws -> ModelMetrics {
        let url = URL(string: "\(Config.cvModelURL)/analyze-landing")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body
        var body = Data()
        let videoData = try Data(contentsOf: videoURL)
        let filename = videoURL.lastPathComponent
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "CVModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "API error: \(text)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        return ModelMetrics(
            kneeValgusDeg: json["knee_valgus_angle"] as? Double ?? 0,
            kneeFlexionDeg: json["knee_flexion_angle"] as? Double ?? 0,
            trunkLeanDeg: json["trunk_lean_deg"] as? Double ?? 0,
            lessScore: json["less_total"] as? Double ?? json["less_score"] as? Double ?? 0,
            riskLevel: json["acl_risk_level"] as? String ?? "UNKNOWN",
            asymmetryIndex: json["asymmetry_index"] as? Double ?? 0
        )
    }
    
    // MARK: - Helpers
    
    private static func gaussianRandom(mean: Double, std: Double) -> Double {
        // Box-Muller transform
        let u1 = Double.random(in: 0.001...1)
        let u2 = Double.random(in: 0.001...1)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return mean + std * z
    }
}
