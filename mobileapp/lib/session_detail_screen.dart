import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'session_manager.dart';
import 'skeleton.dart';
import 'theme.dart';

// Light grey used for captions on the dark readout panel.
const _panelCaption = Color(0xFF8B95A6);

/// Per-session detail screen (pushed route). Wraps the shared [SessionReport].
class SessionDetailScreen extends StatelessWidget {
  final JumpSession session;
  final Athlete? athlete;

  const SessionDetailScreen({super.key, required this.session, this.athlete});

  factory SessionDetailScreen.fromFields({
    Key? key,
    required String sessionTitle,
    required String date,
    required String riskFactor,
    required double maxValgus,
    required String coachingCue,
    required double asymmetry,
  }) {
    return SessionDetailScreen(
      key: key,
      session: JumpSession(
        title: sessionTitle,
        date: date,
        riskFactor: riskFactor,
        maxValgus: maxValgus,
        coachingCue: coachingCue,
        asymmetryIndex: asymmetry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: LColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: LColors.stroke), boxShadow: kCardShadow),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: LColors.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(session.title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1, color: LColors.ink))),
                StatusPill(session.riskFactor.split(' ').first.toUpperCase(), LColors.risk(session.riskFactor)),
              ],
            ),
            const SizedBox(height: 18),
            SessionReport(session: session, athlete: athlete),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHARED SESSION REPORT
// ════════════════════════════════════════════════════════════════════════════

class SessionReport extends StatelessWidget {
  final JumpSession session;
  final Athlete? athlete;
  const SessionReport({super.key, required this.session, this.athlete});

  @override
  Widget build(BuildContext context) {
    final rc = LColors.risk(session.riskFactor);
    final riskLabel = session.riskFactor.toUpperCase().contains('HIGH')
        ? 'High risk'
        : session.riskFactor.toUpperCase().contains('MODERATE')
            ? 'Moderate risk'
            : 'Low risk';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Risk hero ─────────────────────────────────────────────────
        LCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              ScoreRing(
                value: (session.riskScore > 0 ? session.riskScore : 0) / 100,
                color: rc,
                size: 92,
                stroke: 7,
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(session.riskScore > 0 ? session.riskScore.toStringAsFixed(0) : '—', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: rc, height: 1)),
                  const Text('RISK / 100', style: TextStyle(fontSize: 7.5, color: LColors.inkLow, letterSpacing: 0.5)),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(riskLabel, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: rc, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12.5, color: LColors.inkMid, height: 1.4),
                        children: [
                          const TextSpan(text: 'Automated LESS '),
                          TextSpan(text: '${session.lessScore} of 8', style: const TextStyle(fontWeight: FontWeight.w800, color: LColors.ink)),
                          const TextSpan(text: ' error patterns flagged.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // ── Kinematic readout ─────────────────────────────────────────
        Row(children: [
          const OutlineChip('SIG'),
          const SizedBox(width: 8),
          const Text('KINEMATIC READOUT', style: TextStyle(fontSize: 10.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        ]),
        const SizedBox(height: 10),
        SkeletonReplay(session: session),
        const SizedBox(height: 22),

        // ── Key metrics ───────────────────────────────────────────────
        const SectionLabel('KEY METRICS'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricCard(label: 'KNEE FLEXION @ CONTACT', value: session.kneeFlexionIC > 0 ? '${session.kneeFlexionIC.toStringAsFixed(2)}°' : '—', bad: session.kneeFlexionIC > 0 && session.kneeFlexionIC < 20.0),
            _MetricCard(label: 'PEAK KNEE VALGUS', value: '${session.maxValgus.toStringAsFixed(2)}°', bad: session.maxValgus >= 5.0),
            _MetricCard(label: 'ASYMMETRY INDEX', value: '${(session.asymmetryIndex * 100).toStringAsFixed(1)}%', bad: session.asymmetryIndex >= 0.07),
            _MetricCard(label: 'ENERGY ABSORPTION', value: session.energyAbsorption > 0 ? '${session.energyAbsorption.toStringAsFixed(1)}°' : '—', bad: session.energyAbsorption > 0 && session.energyAbsorption < 35.0),
          ],
        ),
        const SizedBox(height: 24),

        // ── Fatigue pillar ────────────────────────────────────────────
        Row(children: const [
          Text('PILLAR 2', style: TextStyle(fontSize: 10.5, color: LColors.red, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          SizedBox(width: 7),
          Text('· FATIGUE', style: TextStyle(fontSize: 10.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 10),
        const Text('Fatigue vulnerability', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: LColors.ink, letterSpacing: -0.6)),
        const SizedBox(height: 8),
        const Text(
          'Injuries happen tired, but most screening is done fresh. LANDR compares the same athlete fresh vs fatigued — how much their mechanics decay.',
          style: TextStyle(fontSize: 13, color: LColors.inkMid, height: 1.55),
        ),
        const SizedBox(height: 16),
        FatiguePillar(session: session),
        const SizedBox(height: 24),

        // ── Trend ─────────────────────────────────────────────────────
        if (athlete != null && athlete!.sessions.length > 1) ...[
          const SectionLabel('PEAK VALGUS TREND'),
          const SizedBox(height: 12),
          LCard(padding: const EdgeInsets.all(18), child: SizedBox(height: 120, child: _Trend(sessions: athlete!.sessions, color: rc))),
          const SizedBox(height: 24),
        ],

        // ── LESS breakdown ────────────────────────────────────────────
        SectionLabel('LESS CRITERION BREAKDOWN', trailing: Text('${session.lessErrors.length} flagged', style: const TextStyle(fontSize: 10, color: LColors.inkLow))),
        const SizedBox(height: 12),
        LCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (int i = 0; i < kLessAllKeys.length; i++)
              _LessRow(criterionKey: kLessAllKeys[i], flagged: session.lessErrors.contains(kLessAllKeys[i]), isLast: i == kLessAllKeys.length - 1),
          ]),
        ),
        const SizedBox(height: 24),

        // ── Coaching ──────────────────────────────────────────────────
        const SectionLabel('AI COACHING FEEDBACK'),
        const SizedBox(height: 12),
        LCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: LColors.navy, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(session.coachingCue, style: const TextStyle(color: LColors.ink, fontSize: 13.5, height: 1.55))),
          ]),
        ),
        const SizedBox(height: 14),
        LCard(
          shadow: false,
          color: LColors.surfaceAlt,
          child: Row(children: const [
            Icon(Icons.info_outline_rounded, color: LColors.inkLow, size: 14),
            SizedBox(width: 8),
            Expanded(child: Text('Decision-support only. Always keep a qualified clinician in the loop.', style: TextStyle(color: LColors.inkLow, fontSize: 11, height: 1.4))),
          ]),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  KINEMATIC READOUT — animated skeleton replay synced to a scrubber + chart
// ════════════════════════════════════════════════════════════════════════════

class SkeletonReplay extends StatefulWidget {
  final JumpSession session;
  const SkeletonReplay({super.key, required this.session});

  @override
  State<SkeletonReplay> createState() => _SkeletonReplayState();
}

class _SkeletonReplayState extends State<SkeletonReplay> with SingleTickerProviderStateMixin {
  static const _clipSeconds = 1.20;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
  bool _playing = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _togglePlay() => setState(() {
        _playing = !_playing;
        _playing ? _c.repeat() : _c.stop();
      });

  void _scrub(double v) => setState(() {
        _playing = false;
        _c.stop();
        _c.value = v.clamp(0.0, 1.0);
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final rc = LColors.risk(s.riskFactor);
    const n = 48;
    final series = List.generate(n, (i) => FlSpot(i.toDouble(), s.valgusAt(i / (n - 1))));
    final maxY = (s.maxValgus * 1.15).clamp(5.0, 60.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LColors.panelStroke),
        boxShadow: kCardShadow,
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final angle = s.valgusAt(t);
          final pose = Pose.landing(t: t, severity: s.severity, arms: 0.5);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: Text('FRONT-VIEW LANDING · DRIVEN BY MEASURED ANGLES', style: TextStyle(fontSize: 8.5, color: _panelCaption, fontWeight: FontWeight.w700, letterSpacing: 0.6, height: 1.3))),
                  const SizedBox(width: 8),
                  Text('${angle.toStringAsFixed(1)}°', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: rc, letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 42,
                      child: Container(
                        decoration: BoxDecoration(color: const Color(0xFF0E121B), borderRadius: BorderRadius.circular(12), border: Border.all(color: LColors.panelStroke)),
                        child: Padding(padding: const EdgeInsets.all(6), child: CustomPaint(painter: SkeletonPainter(pose, color: rc, stroke: 3.5, grid: true, showValgusGuides: true))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 58,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('KNEE VALGUS · DEGREES OVER TIME', style: TextStyle(fontSize: 7.5, color: _panelCaption, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          Expanded(
                            child: LineChart(
                              LineChartData(
                                minX: 0, maxX: (n - 1).toDouble(), minY: 0, maxY: maxY,
                                gridData: const FlGridData(show: false),
                                titlesData: const FlTitlesData(show: false),
                                borderData: FlBorderData(show: false),
                                lineTouchData: const LineTouchData(enabled: false),
                                extraLinesData: ExtraLinesData(verticalLines: [VerticalLine(x: t * (n - 1), color: LColors.cyan, strokeWidth: 1.5)]),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: series, isCurved: true, color: rc, barWidth: 2.5, isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rc.withOpacity(0.25), rc.withOpacity(0.0)])),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                            Text('CONTACT', style: TextStyle(fontSize: 7, color: _panelCaption, fontWeight: FontWeight.w700)),
                            Text('LOWEST', style: TextStyle(fontSize: 7, color: _panelCaption, fontWeight: FontWeight.w700)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 34, height: 34,
                      decoration: const BoxDecoration(color: LColors.cyan, shape: BoxShape.circle),
                      child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: LColors.cyan,
                        inactiveTrackColor: const Color(0xFF2A2F3A),
                        thumbColor: LColors.cyan,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(value: t, onChanged: _scrub),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 40,
                    child: Text('${(t * _clipSeconds).toStringAsFixed(2)}s', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: _panelCaption, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  FATIGUE PILLAR
// ════════════════════════════════════════════════════════════════════════════

class FatiguePillar extends StatefulWidget {
  final JumpSession session;
  const FatiguePillar({super.key, required this.session});

  @override
  State<FatiguePillar> createState() => _FatiguePillarState();
}

class _FatiguePillarState extends State<FatiguePillar> {
  double _fatigue = 0.5;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final vuln = s.vulnerability(_fatigue);
    final Color vc = vuln >= 66 ? LColors.red : vuln >= 40 ? LColors.amber : LColors.green;
    final String vlabel = vuln >= 66 ? 'Vulnerable' : vuln >= 40 ? 'Moderate decay' : 'Resilient';
    final String vbody = vuln >= 66
        ? 'Mechanics degrade substantially when tired — prioritise fatigue-resistant training.'
        : vuln >= 40
            ? 'Some decay under load — reinforce landing mechanics late in sessions.'
            : 'Mechanics hold up well under fatigue — keep maintaining.';

    return Column(
      children: [
        LCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SIMULATE SESSION FATIGUE', style: TextStyle(fontSize: 9.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 16),
              _GradientSlider(value: _fatigue, onChanged: (v) => setState(() => _fatigue = v)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                Text('FRESH', style: TextStyle(fontSize: 9, color: LColors.green, fontWeight: FontWeight.w700)),
                Text('MID-SESSION', style: TextStyle(fontSize: 9, color: LColors.amber, fontWeight: FontWeight.w700)),
                Text('EXHAUSTED', style: TextStyle(fontSize: 9, color: LColors.red, fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LCard(
          child: Row(
            children: [
              ScoreRing(
                value: vuln / 100,
                color: vc,
                size: 84,
                stroke: 7,
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(vuln.toStringAsFixed(0), style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: vc, height: 1)),
                  const Text('VULN / 100', style: TextStyle(fontSize: 6.5, color: LColors.inkLow, letterSpacing: 0.5)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vlabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: vc)),
                    const SizedBox(height: 5),
                    Text(vbody, style: const TextStyle(fontSize: 12, color: LColors.inkMid, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Align(alignment: Alignment.centerLeft, child: Text('FRESH VS FATIGUED', style: TextStyle(fontSize: 9.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: SkeletonTile(pose: Pose.landing(t: 0.5, severity: s.freshSeverity, arms: 0.5), color: LColors.green, label: 'FRESH', valgusGuides: true)),
            const SizedBox(width: 12),
            Expanded(child: SkeletonTile(pose: Pose.landing(t: 0.5, severity: s.fatiguedSeverity(_fatigue), arms: 0.5), color: LColors.red, label: 'FATIGUED', valgusGuides: true)),
          ],
        ),
      ],
    );
  }
}

/// Green→amber→red gradient track with draggable thumb.
class _GradientSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _GradientSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void update(double dx) => onChanged((dx / w).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          child: SizedBox(
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(height: 8, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: const LinearGradient(colors: [LColors.green, LColors.amber, LColors.red]))),
                Positioned(
                  left: (value * w - 12).clamp(0.0, w - 24),
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: LColors.stroke, width: 2), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Trend ─────────────────────────────────────────────────────────────────────

class _Trend extends StatelessWidget {
  final List<JumpSession> sessions;
  final Color color;
  const _Trend({required this.sessions, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = sessions.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.maxValgus)).toList();
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: LColors.stroke, strokeWidth: 1)),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, reservedSize: 18, getTitlesWidget: (v, m) {
            final i = v.toInt();
            if (i < 0 || i >= sessions.length) return const SizedBox();
            return Text('S${i + 1}', style: const TextStyle(color: LColors.inkLow, fontSize: 9));
          })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 5, reservedSize: 28, getTitlesWidget: (v, m) => Text('${v.toInt()}°', style: const TextStyle(color: LColors.inkLow, fontSize: 9)))),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, color: color, barWidth: 2.5, isStrokeCapRound: true,
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withOpacity(0.18), color.withOpacity(0.0)])),
            dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: i == spots.length - 1 ? 5 : 2.5, color: color, strokeWidth: 0)),
          ),
        ],
      ),
    );
  }
}

// ── Metric card ───────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label, value;
  final bool bad;
  const _MetricCard({required this.label, required this.value, required this.bad});

  @override
  Widget build(BuildContext context) {
    return LCard(
      shadow: false,
      color: LColors.surfaceAlt,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: LColors.ink, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(bad ? Icons.arrow_drop_up_rounded : Icons.check_rounded, color: bad ? LColors.red : LColors.green, size: 15),
            const SizedBox(width: 2),
            Text(bad ? 'outside range' : 'in range', style: TextStyle(color: bad ? LColors.red : LColors.green, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    );
  }
}

// ── LESS row ────────────────────────────────────────────────────────────────

class _LessRow extends StatelessWidget {
  final String criterionKey;
  final bool flagged, isLast;
  const _LessRow({required this.criterionKey, required this.flagged, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final label = kLessLabels[criterionKey] ?? criterionKey;
    final color = flagged ? LColors.red : LColors.green;
    final icon = flagged ? Icons.close_rounded : Icons.check_rounded;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
              child: Icon(icon, color: color, size: 13),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: flagged ? LColors.ink : LColors.inkMid, fontWeight: flagged ? FontWeight.w600 : FontWeight.normal))),
            Text(flagged ? 'ERROR' : 'PASS', style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ]),
        ),
        if (!isLast) const Divider(height: 1, color: LColors.stroke, indent: 50),
      ],
    );
  }
}
