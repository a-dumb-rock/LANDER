import 'package:flutter/material.dart';

class SessionDetailScreen extends StatelessWidget {
  final String sessionTitle;
  final String date;
  final String riskFactor;
  final double maxValgus;
  final String coachingCue;
  final double asymmetry;

  const SessionDetailScreen({
    super.key,
    required this.sessionTitle,
    required this.date,
    required this.riskFactor,
    required this.maxValgus,
    required this.coachingCue,
    required this.asymmetry,
  });

  Color _getRiskColor() {
    if (riskFactor.contains("HIGH")) return Colors.redAccent;
    if (riskFactor.contains("MODERATE")) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    Color riskColor = _getRiskColor();

    return Scaffold(
      appBar: AppBar(
        title: Text(sessionTitle),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(date, style: const TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 16),
            
            // ACL Risk Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: riskColor, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ACL INJURY RISK FACTOR", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    riskFactor, 
                    style: TextStyle(color: riskColor, fontSize: 28, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            const Text("Key Biomechanical Markers", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            _buildMetricTile("Peak Knee Valgus", "${maxValgus.toStringAsFixed(1)}°", "Inward collapse angle"),
            _buildMetricTile("Asymmetry Index", "${(asymmetry * 100).toStringAsFixed(1)}%", "Left vs Right loading bias"),
            
            const SizedBox(height: 24),
            const Text("AI Coaching Feedback", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Coaching Cue Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      coachingCue,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String title, String value, String subtitle) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}