import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// ════════════════════════════════════════════════════════════════════════════
///  PROCEDURAL POSE ENGINE
///  A front-view stick figure whose knees "cave" inward (dynamic valgus) in
///  proportion to a measured severity, animated across a normalized landing
///  timeline. This is a visualization driven by the measured angles — not a
///  per-frame motion capture.
/// ════════════════════════════════════════════════════════════════════════════

/// Bell curve peaking at the lowest point of the landing (t ≈ 0.5).
double _bell(double t) => math.exp(-math.pow(t - 0.5, 2) / (2 * 0.035));

class Pose {
  final Offset head;
  final double headR;
  final Offset neck, shoulderL, shoulderR, elbowL, elbowR, handL, handR;
  final Offset hipC, hipL, hipR, kneeL, kneeR, ankleL, ankleR;

  const Pose({
    required this.head,
    required this.headR,
    required this.neck,
    required this.shoulderL,
    required this.shoulderR,
    required this.elbowL,
    required this.elbowR,
    required this.handL,
    required this.handR,
    required this.hipC,
    required this.hipL,
    required this.hipR,
    required this.kneeL,
    required this.kneeR,
    required this.ankleL,
    required this.ankleR,
  });

  /// Build a landing pose.
  /// [t]        normalized timeline 0..1 (0 = initial contact, ~0.5 = lowest).
  /// [severity] 0..1 amount of dynamic valgus (knees-in collapse).
  /// [arms]     0..1 how much arms raise for balance.
  factory Pose.landing({required double t, required double severity, double arms = 0.5}) {
    final phase = _bell(t).clamp(0.0, 1.0);     // 0 at ends, 1 at lowest
    final cave = 0.115 * severity * phase;       // inward knee travel
    final drop = 0.055 * phase;                  // hips sink during flexion
    final armRaise = 0.10 * arms * phase;

    final hipCy = 0.515 + drop;
    return Pose(
      head: Offset(0.5, 0.135 + drop * 0.7),
      headR: 0.058,
      neck: Offset(0.5, 0.225 + drop * 0.7),
      shoulderL: Offset(0.405, 0.245 + drop * 0.7),
      shoulderR: Offset(0.595, 0.245 + drop * 0.7),
      elbowL: Offset(0.355 - armRaise, 0.385 - armRaise * 1.4 + drop * 0.5),
      elbowR: Offset(0.645 + armRaise, 0.385 - armRaise * 1.4 + drop * 0.5),
      handL: Offset(0.335 - armRaise * 1.6, 0.515 - armRaise * 3.2 + drop * 0.3),
      handR: Offset(0.665 + armRaise * 1.6, 0.515 - armRaise * 3.2 + drop * 0.3),
      hipC: Offset(0.5, hipCy),
      hipL: Offset(0.448, hipCy + 0.01),
      hipR: Offset(0.552, hipCy + 0.01),
      kneeL: Offset(0.435 + cave, 0.70 + drop * 0.5),
      kneeR: Offset(0.565 - cave, 0.70 + drop * 0.5),
      ankleL: const Offset(0.43, 0.905),
      ankleR: const Offset(0.57, 0.905),
    );
  }
}

/// Paints a [Pose] inside the given box.
class SkeletonPainter extends CustomPainter {
  final Pose pose;
  final Color color;
  final double stroke;
  final bool grid;
  final bool showValgusGuides;

  SkeletonPainter(
    this.pose, {
    this.color = LColors.red,
    this.stroke = 4,
    this.grid = false,
    this.showValgusGuides = false,
  });

  Offset _p(Offset n, Size s) => Offset(n.dx * s.width, n.dy * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    if (grid) {
      final g = Paint()
        ..color = Colors.white.withOpacity(0.04)
        ..strokeWidth = 1;
      const step = 26.0;
      for (double x = 0; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
      }
      for (double y = 0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
      }
    }

    final limb = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glow = Paint()
      ..color = color.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    void line(Offset a, Offset b) {
      final pa = _p(a, size), pb = _p(b, size);
      canvas.drawLine(pa, pb, glow);
      canvas.drawLine(pa, pb, limb);
    }

    // Optional vertical reference lines hip→ankle (shows the cave angle)
    if (showValgusGuides) {
      final ref = Paint()
        ..color = color.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      void dashed(Offset a, Offset b) {
        final pa = _p(a, size), pb = _p(b, size);
        const dash = 5.0, gap = 4.0;
        final total = (pb - pa).distance;
        final dir = (pb - pa) / total;
        double d = 0;
        while (d < total) {
          final s = pa + dir * d;
          final e = pa + dir * math.min(d + dash, total);
          canvas.drawLine(s, e, ref);
          d += dash + gap;
        }
      }
      dashed(pose.hipL, Offset(pose.hipL.dx, pose.ankleL.dy));
      dashed(pose.hipR, Offset(pose.hipR.dx, pose.ankleR.dy));
    }

    // Body
    line(pose.neck, pose.hipC);                 // spine
    line(pose.shoulderL, pose.shoulderR);        // shoulders
    line(pose.shoulderL, pose.elbowL);
    line(pose.elbowL, pose.handL);
    line(pose.shoulderR, pose.elbowR);
    line(pose.elbowR, pose.handR);
    line(pose.hipL, pose.hipR);                  // pelvis
    line(pose.hipL, pose.kneeL);                 // thighs
    line(pose.kneeL, pose.ankleL);               // shins
    line(pose.hipR, pose.kneeR);
    line(pose.kneeR, pose.ankleR);

    // Knee markers (emphasise the valgus point)
    for (final k in [pose.kneeL, pose.kneeR]) {
      canvas.drawCircle(_p(k, size), stroke * 1.1, Paint()..color = color);
    }

    // Head
    final hc = _p(pose.head, size);
    final hr = pose.headR * size.height;
    canvas.drawCircle(hc, hr, glow);
    canvas.drawCircle(hc, hr, limb);
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter old) =>
      old.pose != pose || old.color != color || old.stroke != stroke;
}

/// A framed skeleton tile (dark inner panel, optional grid + label).
class SkeletonTile extends StatelessWidget {
  final Pose pose;
  final Color color;
  final String? label;
  final double aspect;
  final bool grid;
  final bool valgusGuides;
  final EdgeInsetsGeometry padding;

  const SkeletonTile({
    super.key,
    required this.pose,
    required this.color,
    this.label,
    this.aspect = 0.78,
    this.grid = true,
    this.valgusGuides = false,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          color: LColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: LColors.panelStroke),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: padding,
                child: CustomPaint(
                  painter: SkeletonPainter(pose, color: color, grid: grid, showValgusGuides: valgusGuides),
                ),
              ),
            ),
            if (label != null)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(label!,
                      style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
