import 'package:flutter/material.dart';

class JumpSession {
  final String title;
  final String date;
  final String riskFactor;       // e.g., "HIGH RISK", "LOW RISK"
  final double maxValgus;        // Max degrees calculated
  final String coachingCue;      // Exercise tip
  final double asymmetryIndex;   // Left vs Right bias

  JumpSession({
    required this.title,
    required this.date,
    required this.riskFactor,
    required this.maxValgus,
    required this.coachingCue,
    required this.asymmetryIndex,
  });
}

class SessionData {
  // Baseline initial history logs mapping directly to your python keys
  static final List<JumpSession> history = [
    JumpSession(
      title: "Landing Session #11", 
      date: "June 22, 2026", 
      riskFactor: "MODERATE RISK", 
      maxValgus: 6.8, 
      coachingCue: "Slight inward knee collapse. Monitor hip stability during fatigue.",
      asymmetryIndex: 0.045
    ),
    JumpSession(
      title: "Landing Session #12", 
      date: "June 24, 2026", 
      riskFactor: "LOW RISK", 
      maxValgus: 3.2, 
      coachingCue: "Excellent alignment. Mechanics look safe!",
      asymmetryIndex: 0.021
    ),
  ];

  // Call this function inside your http response processing map in main.dart!
  static void addSessionFromBackend(Map<String, dynamic> jsonResponse) {
    int nextSessionNumber = history.length + 1;
    
    // Safely extracting from nested python map: results["acl_risk_assessment"]
    final assessment = jsonResponse['acl_risk_assessment'] ?? {};
    
    history.add(
      JumpSession(
        title: "Landing Session #$nextSessionNumber",
        date: "June 24, 2026",
        riskFactor: assessment['risk_factor'] ?? "LOW RISK",
        maxValgus: (assessment['max_valgus_observed_deg'] ?? 0.0).toDouble(),
        coachingCue: assessment['coaching_cue'] ?? "Good landing form.",
        asymmetryIndex: (jsonResponse['asymmetry_index'] ?? 0.0).toDouble(),
      ),
    );
  }
}