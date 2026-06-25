import 'package:flutter/material.dart';

class JumpSession {
  final String title;
  final String date;
  final String riskFactor;       // e.g., "High Risk", "Low Risk"
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
  // Baseline initial history logs
  static final List<JumpSession> history = [
    JumpSession(
      title: "Landing Session #11", 
      date: "June 22, 2026", 
      riskFactor: "Moderate Risk", 
      maxValgus: 6.8, 
      coachingCue: "Slight inward knee collapse. Monitor hip stability during fatigue.",
      asymmetryIndex: 0.045
    ),
    JumpSession(
      title: "Landing Session #12", 
      date: "June 24, 2026", 
      riskFactor: "Low Risk", 
      maxValgus: 3.2, 
      coachingCue: "Excellent alignment. Mechanics look safe!",
      asymmetryIndex: 0.021
    ),
  ];

  // Syncs precisely with keys declared in server.py
  static void addSessionFromBackend(Map<String, dynamic> jsonResponse) {
    int nextSessionNumber = history.length + 1;
    
    history.add(
      JumpSession(
        title: "Landing Session #$nextSessionNumber",
        date: "June 24, 2026",
        riskFactor: jsonResponse['acl_risk_level'] ?? "Low Risk",
        maxValgus: (jsonResponse['knee_valgus_angle'] ?? jsonResponse['knee_valgus'] ?? 0.0).toDouble(),
        coachingCue: jsonResponse['feedback_message'] ?? "Good landing form.",
        asymmetryIndex: (jsonResponse['asymmetry_index'] ?? 0.0).toDouble(),
      ),
    );
  }

  // Deletes an item from history safely by reference
  static void deleteSession(JumpSession session) {
    history.remove(session);
  }
}