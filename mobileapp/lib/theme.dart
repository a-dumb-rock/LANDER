import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════════
///  LANDR DESIGN SYSTEM — light / editorial
///  Warm off-white canvas, white cards with hairline borders + soft shadows,
///  near-black navy ink. The only dark surfaces are the "readout" panels that
///  host the skeleton + charts.
/// ════════════════════════════════════════════════════════════════════════════

class LColors {
  // Canvas + surfaces
  static const bg         = Color(0xFFF2F2EF);
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFFAFAF8);
  static const stroke     = Color(0xFFE9E9E4);
  static const strokeHi   = Color(0xFFDEDED8);

  // Ink
  static const ink     = Color(0xFF1A1C22);
  static const inkMid  = Color(0xFF8B8F98);
  static const inkLow  = Color(0xFFB6BAC2);

  // Dark "readout" panel (skeleton + chart host)
  static const panel       = Color(0xFF151922);
  static const panelStroke = Color(0xFF272C36);

  // Brand + status
  static const navy   = Color(0xFF20242C);  // dark button / Screen nav
  static const red    = Color(0xFFE5383B);
  static const green  = Color(0xFF2EAE63);
  static const cyan   = Color(0xFF16C2CE);
  static const amber  = Color(0xFFF2A93B);
  static const slate  = Color(0xFF6B7280);

  static Color risk(String riskFactor) {
    final r = riskFactor.toUpperCase();
    if (r.contains('HIGH')) return red;
    if (r.contains('MODERATE')) return amber;
    return green;
  }
}

/// Soft card shadow used across the light surfaces.
const List<BoxShadow> kCardShadow = [
  BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 6)),
  BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
];

/// ── LANDR wordmark: LAND + red R ────────────────────────────────────────────
class LandrWordmark extends StatelessWidget {
  final double size;
  final bool showVersion;
  const LandrWordmark({super.key, this.size = 22, this.showVersion = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: LColors.ink),
            children: const [
              TextSpan(text: 'LAND'),
              TextSpan(text: 'R', style: TextStyle(color: LColors.red)),
            ],
          ),
        ),
        if (showVersion) ...[
          const SizedBox(width: 8),
          const Text('v2 · fatigue-aware',
              style: TextStyle(fontSize: 11, color: LColors.inkMid, fontWeight: FontWeight.w500, letterSpacing: 0.2)),
        ],
      ],
    );
  }
}

/// ── White surface card ──────────────────────────────────────────────────────
class LCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final bool shadow;
  const LCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.onTap,
    this.color,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? LColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: LColors.stroke),
        boxShadow: shadow ? kCardShadow : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
  }
}

/// ── Section label: tracked uppercase grey, optional leading icon + trailing ──
class SectionLabel extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: LColors.inkLow), const SizedBox(width: 7)],
        Text(text, style: const TextStyle(fontSize: 10.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// ── Outline "SIG"-style chip ────────────────────────────────────────────────
class OutlineChip extends StatelessWidget {
  final String label;
  final Color color;
  const OutlineChip(this.label, {super.key, this.color = LColors.inkMid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
    );
  }
}

/// ── Status pill: dot + label on a tinted ground ─────────────────────────────
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

/// ── Dark navy primary button ────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double height;
  final bool iconLeading;
  const PrimaryButton({super.key, required this.label, required this.icon, required this.onTap, this.height = 54, this.iconLeading = true});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Icon(icon, color: Colors.white, size: 19),
      const SizedBox(width: 9),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: 0.2)),
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: LColors.navy,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: iconLeading ? children : children.reversed.toList()),
      ),
    );
  }
}

/// ── Solid-color monogram avatar ─────────────────────────────────────────────
class Monogram extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const Monogram(this.text, this.color, {super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Center(
        child: Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.32, letterSpacing: 0.5)),
      ),
    );
  }
}

/// ── Circular score ring ─────────────────────────────────────────────────────
class ScoreRing extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double size;
  final double stroke;
  final Widget center;
  const ScoreRing({super.key, required this.value, required this.color, required this.center, this.size = 92, this.stroke = 7});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0, 1), color, stroke),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final double stroke;
  _RingPainter(this.value, this.color, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rad = (math.min(size.width, size.height) - stroke) / 2;
    const start = math.pi * 0.72;
    const sweep = math.pi * 1.56;
    canvas.drawArc(Rect.fromCircle(center: c, radius: rad), start, sweep, false,
        Paint()..color = color.withOpacity(0.14)..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round);
    canvas.drawArc(Rect.fromCircle(center: c, radius: rad), start, sweep * value, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value || old.color != color;
}

/// ── Frosted-glass wrapper (used over the camera) ────────────────────────────
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final Color color;
  final Border? border;
  const Glass({super.key, required this.child, this.radius = 20, this.blur = 16, this.color = const Color(0x1FFFFFFF), this.border});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: border ?? Border.all(color: Colors.white.withOpacity(0.14))),
          child: child,
        ),
      ),
    );
  }
}
