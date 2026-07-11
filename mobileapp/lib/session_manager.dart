import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Human-readable labels for each LESS criterion key.
const Map<String, String> kLessLabels = {
  'knee_flexion_at_contact':    'Insufficient knee flexion at contact',
  'knee_valgus_at_contact':     'Knee valgus at initial contact',
  'trunk_flexion_at_contact':   'Insufficient trunk lean at contact',
  'knee_flexion_displacement':  'Poor energy absorption (small flexion range)',
  'knee_valgus_at_lowest':      'Knee valgus at lowest point',
  'peak_knee_valgus':           'Excessive peak knee valgus',
  'landing_asymmetry':          'Asymmetric limb loading',
  'overall_impression':         'Poor overall landing pattern',
};

/// All possible LESS criterion keys, in display order.
const List<String> kLessAllKeys = [
  'knee_flexion_at_contact',
  'knee_valgus_at_contact',
  'trunk_flexion_at_contact',
  'knee_flexion_displacement',
  'knee_valgus_at_lowest',
  'peak_knee_valgus',
  'landing_asymmetry',
  'overall_impression',
];

double _bell(double t) => math.exp(-math.pow(t - 0.5, 2) / (2 * 0.035));

/// Within-athlete measurement precision (RMSE, degrees), from LANDR's lab-mocap
/// validation (OpenCap, held-out subjects). Because each athlete is compared to
/// their OWN history, the per-athlete offset cancels and these are the numbers
/// that govern trend detection. A change smaller than this is measurement noise,
/// NOT real buildup — the trend logic below refuses to flag inside this band so
/// the app never cries wolf on a wiggle.
const double kValgusPrecisionDeg = 5.0;   // peak knee valgus (the #1 ACL predictor)
const double kFlexionPrecisionDeg = 5.0;  // knee flexion at contact

enum TrendStatus {
  insufficient, // not enough prior sessions to establish a baseline
  rising,       // moved in the injurious direction beyond measurement noise
  stable,       // change within measurement noise
  improving,    // moved in the protective direction beyond measurement noise
}

/// A metric's change for one session vs the athlete's own prior baseline.
class MetricTrend {
  final double? baseline; // median of the athlete's sessions BEFORE this one
  final double? current;
  final TrendStatus status;
  const MetricTrend({this.baseline, this.current, required this.status});

  double? get delta =>
      (baseline != null && current != null) ? current! - baseline! : null;
}

double? _median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2.0;
}

class JumpSession {
  final String title;
  final String date;
  final String riskFactor;        // "Low Risk" / "Moderate Risk" / "High Risk"
  final double maxValgus;         // Peak knee valgus (degrees)
  final String coachingCue;       // AI coaching feedback
  final double asymmetryIndex;    // Left vs Right loading bias (0–1)

  // Extended biomechanical fields
  final int lessScore;            // LESS total errors (0–8)
  final double riskScore;         // Composite risk score (0–100)
  final double kneeFlexionIC;     // Knee flexion at initial contact (degrees)
  final double trunkFlexion;      // Trunk lean at initial contact (degrees)
  final double energyAbsorption;  // Knee flexion displacement / absorption range (degrees)
  final List<String> lessErrors;  // LESS criterion keys that flagged as errors
  final bool isDemo;              // true = hand-authored placeholder; false = measured by the engine

  JumpSession({
    required this.title,
    required this.date,
    required this.riskFactor,
    required this.maxValgus,
    required this.coachingCue,
    required this.asymmetryIndex,
    this.lessScore = 0,
    this.riskScore = 0.0,
    this.kneeFlexionIC = 0.0,
    this.trunkFlexion = 0.0,
    this.energyAbsorption = 0.0,
    this.lessErrors = const [],
    this.isDemo = true,
  });

  // ── Visualization helpers (drive the procedural skeleton / charts) ─────────

  /// 0..1 amount of dynamic valgus used to drive the skeleton "knees-in" cave.
  double get severity => (maxValgus / 30.0).clamp(0.0, 1.0);

  /// Knee-valgus angle (degrees) at normalized landing time [t] (0..1).
  double valgusAt(double t) {
    final base = maxValgus * 0.18;
    return base + (maxValgus - base) * _bell(t);
  }

  /// Sampled knee-valgus-over-time series for charting.
  List<double> valgusSeries(int n) =>
      List.generate(n, (i) => valgusAt(i / (n - 1)));

  // ── Fatigue simulation (Pillar 2) ──────────────────────────────────────────

  /// Knee-cave severity when the athlete is fresh (mechanics hold up better).
  double get freshSeverity => (severity * 0.55).clamp(0.0, 1.0);

  /// Knee-cave severity at a given session [fatigue] (0 = fresh, 1 = exhausted).
  double fatiguedSeverity(double fatigue) =>
      (freshSeverity + fatigue * (0.45 + severity * 0.45)).clamp(0.0, 1.0);

  /// Fatigue-vulnerability score (0..100) at the given [fatigue] level.
  double vulnerability(double fatigue) =>
      (fatiguedSeverity(fatigue) * 100).clamp(0.0, 100.0);

  /// Build a session from a backend JSON payload (full pipeline or legacy flat).
  factory JumpSession.fromBackend(Map<String, dynamic> json, int index) {
    // --- LESS errors ---
    final List<String> errors = [];
    final dynamic lessBlock = json['less'];
    if (lessBlock != null && lessBlock['items'] != null) {
      for (final dynamic item in (lessBlock['items'] as List)) {
        if (item['error'] == true) {
          final String? key = item['key'] as String?;
          if (key != null) errors.add(key);
        }
      }
    }

    // --- Peak valgus: nested format first, then legacy flat keys ---
    double valgus = 0.0;
    final dynamic metricsBlock = json['metrics'];
    if (metricsBlock != null) {
      final dynamic pv = metricsBlock['peak_valgus_deg'];
      if (pv != null) {
        final double l = (pv['left'] ?? 0.0).toDouble().abs();
        final double r = (pv['right'] ?? 0.0).toDouble().abs();
        valgus = l > r ? l : r;
      }
    }
    if (valgus == 0.0) {
      valgus = (json['knee_valgus_angle'] ?? json['knee_valgus'] ?? 0.0).toDouble();
    }

    // --- Risk ---
    String riskFactor = "Low Risk";
    final dynamic riskBlock = json['risk'];
    if (riskBlock != null) {
      riskFactor = _capitalizeRisk(riskBlock['category'] as String? ?? 'low');
    } else {
      riskFactor = json['acl_risk_level'] as String? ?? "Low Risk";
    }
    final double riskScore =
        riskBlock != null ? (riskBlock['score_0_100'] ?? 0.0).toDouble() : 0.0;

    // --- Nested metrics ---
    final dynamic ic = metricsBlock?['at_initial_contact'];
    final double kneeFlexionIC = ic != null ? (ic['knee_flexion_deg'] ?? 0.0).toDouble() : 0.0;
    final double trunkFlexion = ic != null ? (ic['trunk_flexion_deg'] ?? 0.0).toDouble() : 0.0;
    final double energyAbsorption = metricsBlock != null
        ? (metricsBlock['knee_flexion_displacement_deg'] ?? 0.0).toDouble()
        : 0.0;
    final double asymmetry = metricsBlock != null
        ? (metricsBlock['asymmetry_index'] ?? 0.0).toDouble()
        : (json['asymmetry_index'] ?? 0.0).toDouble();

    return JumpSession(
      title: "Landing Session #$index",
      date: _todayLabel(),
      riskFactor: riskFactor,
      maxValgus: valgus,
      coachingCue: json['feedback_message'] as String? ??
          json['report'] as String? ??
          "Analysis complete.",
      asymmetryIndex: asymmetry,
      lessScore: lessBlock != null ? (lessBlock['total'] ?? 0) as int : 0,
      riskScore: riskScore,
      kneeFlexionIC: kneeFlexionIC,
      trunkFlexion: trunkFlexion,
      energyAbsorption: energyAbsorption,
      lessErrors: errors,
      isDemo: false, // came from the engine analysing a real clip
    );
  }
}

/// ── Athlete (roster entry) ────────────────────────────────────────────────────
class Athlete {
  final String id;
  final String firstName;
  final String lastName;
  final String sport;
  final String ageCode;     // e.g. "F16", "M17"
  final Color accent;
  final List<JumpSession> sessions;

  Athlete({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.sport,
    required this.ageCode,
    required this.accent,
    List<JumpSession>? sessions,
  }) : sessions = sessions ?? [];

  String get fullName => '$firstName $lastName';
  String get monogram =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();
  bool get screened => sessions.isNotEmpty;
  JumpSession? get latest => sessions.isEmpty ? null : sessions.last;

  /// Trend of [metric] for session [s] vs this athlete's baseline (the median of
  /// their sessions BEFORE [s]). This is the ACL-BUILDUP signal: comparing an
  /// athlete to their own history cancels their fixed per-athlete offset, so the
  /// change is measured at ~precision (see [kValgusPrecisionDeg]). Changes within
  /// that band are reported as [TrendStatus.stable] rather than false alarms.
  ///
  /// [higherIsWorse]: true for valgus (more cave = worse), false for knee flexion
  /// at contact (less flexion = stiffer landing = worse).
  MetricTrend trendAt(
    JumpSession s,
    double Function(JumpSession) metric,
    double precision, {
    bool higherIsWorse = true,
  }) {
    final i = sessions.indexOf(s);
    if (i < 1) return const MetricTrend(status: TrendStatus.insufficient);
    final baseline = _median(sessions.sublist(0, i).map(metric).toList());
    final current = metric(s);
    if (baseline == null) return const MetricTrend(status: TrendStatus.insufficient);
    final d = current - baseline;
    TrendStatus status;
    if (d.abs() <= precision) {
      status = TrendStatus.stable;
    } else if ((d > 0) == higherIsWorse) {
      status = TrendStatus.rising;
    } else {
      status = TrendStatus.improving;
    }
    return MetricTrend(baseline: baseline, current: current, status: status);
  }

  /// Peak-valgus buildup for [s] vs the athlete's own baseline (the ACL metric).
  MetricTrend valgusTrendAt(JumpSession s) =>
      trendAt(s, (x) => x.maxValgus, kValgusPrecisionDeg, higherIsWorse: true);
}

/// ── Roster (source of truth for athletes + active selection) ──────────────────
class RosterData {
  static final List<Athlete> athletes = [
    Athlete(
      id: 'maya',
      firstName: 'Maya',
      lastName: 'Okonkwo',
      sport: 'Soccer',
      ageCode: 'F16',
      accent: const Color(0xFFE5383B),
      sessions: [
        JumpSession(
          title: "Landing Session #1",
          date: "June 20, 2026",
          riskFactor: "High Risk",
          maxValgus: 12.4,
          coachingCue: "High knee valgus detected. Focus on glute-medius activation and landing softly with knees tracking over toes.",
          asymmetryIndex: 0.087,
          lessScore: 5,
          riskScore: 71.0,
          kneeFlexionIC: 14.2,
          trunkFlexion: 8.5,
          energyAbsorption: 28.0,
          lessErrors: ['knee_flexion_at_contact', 'knee_valgus_at_contact', 'trunk_flexion_at_contact', 'peak_knee_valgus', 'landing_asymmetry'],
        ),
        JumpSession(
          title: "Landing Session #2",
          date: "June 22, 2026",
          riskFactor: "Moderate Risk",
          maxValgus: 6.8,
          coachingCue: "Slight inward knee collapse. Monitor hip stability during fatigue.",
          asymmetryIndex: 0.045,
          lessScore: 3,
          riskScore: 42.0,
          kneeFlexionIC: 18.5,
          trunkFlexion: 12.0,
          energyAbsorption: 38.0,
          lessErrors: ['knee_valgus_at_contact', 'knee_flexion_displacement', 'landing_asymmetry'],
        ),
        JumpSession(
          title: "Landing Session #3",
          date: "June 24, 2026",
          riskFactor: "High Risk",
          maxValgus: 11.6,
          coachingCue: "Valgus returned under load. Prioritise fatigue-resistant single-leg landings this week.",
          asymmetryIndex: 0.072,
          lessScore: 5,
          riskScore: 68.0,
          kneeFlexionIC: 15.1,
          trunkFlexion: 9.4,
          energyAbsorption: 30.0,
          lessErrors: ['knee_flexion_at_contact', 'knee_valgus_at_contact', 'peak_knee_valgus', 'knee_valgus_at_lowest', 'landing_asymmetry'],
        ),
        // DEMO seed (fake, like the others) — illustrates the TRENDING UP buildup
        // state: 16.9° is +5.3° over Maya's 11.6° baseline, past the 5° noise floor.
        JumpSession(
          title: "Landing Session #4",
          date: "June 27, 2026",
          riskFactor: "High Risk",
          maxValgus: 16.9,
          coachingCue: "Valgus spiked well beyond baseline under fatigue. Prioritise fatigue-resistant single-leg landings this week; re-screen in 3 days.",
          asymmetryIndex: 0.094,
          lessScore: 6,
          riskScore: 74.0,
          kneeFlexionIC: 13.8,
          trunkFlexion: 8.0,
          energyAbsorption: 27.0,
          lessErrors: ['knee_flexion_at_contact', 'knee_valgus_at_contact', 'trunk_flexion_at_contact', 'peak_knee_valgus', 'knee_valgus_at_lowest', 'landing_asymmetry'],
        ),
      ],
    ),
    Athlete(
      id: 'devin',
      firstName: 'Devin',
      lastName: 'Park',
      sport: 'Basketball',
      ageCode: 'M17',
      accent: const Color(0xFF2EAE63),
      sessions: [
        JumpSession(
          title: "Landing Session #1",
          date: "June 19, 2026",
          riskFactor: "Low Risk",
          maxValgus: 3.4,
          coachingCue: "Clean, symmetric mechanics. Keep reinforcing soft, quiet landings.",
          asymmetryIndex: 0.018,
          lessScore: 1,
          riskScore: 16.0,
          kneeFlexionIC: 25.0,
          trunkFlexion: 18.0,
          energyAbsorption: 50.0,
          lessErrors: ['knee_flexion_at_contact'],
        ),
        JumpSession(
          title: "Landing Session #2",
          date: "June 23, 2026",
          riskFactor: "Low Risk",
          maxValgus: 4.1,
          coachingCue: "Mechanics holding up well. Watch for late-session valgus creep.",
          asymmetryIndex: 0.026,
          lessScore: 2,
          riskScore: 22.0,
          kneeFlexionIC: 23.0,
          trunkFlexion: 16.0,
          energyAbsorption: 46.0,
          lessErrors: ['knee_flexion_at_contact', 'landing_asymmetry'],
        ),
      ],
    ),
    Athlete(
      id: 'sofia',
      firstName: 'Sofia',
      lastName: 'Reyes',
      sport: 'Volleyball',
      ageCode: 'F15',
      accent: const Color(0xFF6B7280),
      sessions: [],
    ),
    // ── REAL data ─────────────────────────────────────────────────────────────
    // Unlike every session above (hand-authored placeholders), this one was
    // MEASURED by the LANDR engine: two-view analysis of a real drop-vertical-jump
    // (OpenCap LabValidation, subject 08 / DJ1) — the same clip used to validate
    // accuracy against motion capture. Numbers are the engine's actual output.
    Athlete(
      id: 'opencap08',
      firstName: 'OpenCap',
      lastName: 'Subject 08',
      sport: 'Validated capture · real',
      ageCode: 'LAB',
      accent: const Color(0xFF16C2CE),
      sessions: [
        JumpSession(
          title: "Drop-vertical-jump · DJ1",
          date: "Analysed Jul 10, 2026",
          riskFactor: "Low Risk",
          maxValgus: 8.8,
          coachingCue: "Engine-measured from real video. Deep, soft landing — 31° knee flexion at contact, 88° at lowest, valgus controlled (2° contact / 4° lowest). Even out minor left/right asymmetry.",
          asymmetryIndex: 0.185,
          lessScore: 1,
          riskScore: 15.9,
          kneeFlexionIC: 31.1,
          trunkFlexion: 20.7,
          energyAbsorption: 56.9,
          lessErrors: ['landing_asymmetry'],
          isDemo: false,
        ),
      ],
    ),
  ];

  static String selectedId = athletes.first.id;

  static Athlete get selected =>
      athletes.firstWhere((a) => a.id == selectedId, orElse: () => athletes.first);

  static void select(String id) => selectedId = id;

  /// Append a backend analysis to the currently-selected athlete.
  static void addSessionFromBackend(Map<String, dynamic> json) {
    final a = selected;
    a.sessions.add(JumpSession.fromBackend(json, a.sessions.length + 1));
  }

  static void deleteSession(Athlete athlete, JumpSession session) {
    athlete.sessions.remove(session);
  }
}

String _capitalizeRisk(String raw) {
  switch (raw.toLowerCase()) {
    case 'high': return 'High Risk';
    case 'moderate': return 'Moderate Risk';
    default: return 'Low Risk';
  }
}

String _todayLabel() {
  final now = DateTime.now();
  const months = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${months[now.month]} ${now.day}, ${now.year}';
}
