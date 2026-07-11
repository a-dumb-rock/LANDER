import 'package:flutter/material.dart';
import 'theme.dart';

/// Pre-test setup guide shown before the camera screen.
/// Walks the athlete/clinician through DVJ setup and the correct movement cue.
class PreTestScreen extends StatefulWidget {
  final VoidCallback onReady;
  const PreTestScreen({super.key, required this.onReady});

  @override
  State<PreTestScreen> createState() => _PreTestScreenState();
}

class _PreTestScreenState extends State<PreTestScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _pages = [_PageSetup(), _PageMovement(), _PageCamera()];

  void _next() {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    } else {
      widget.onReady();
    }
  }

  void _prev() {
    if (_page > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: LColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  if (_page > 0)
                    GestureDetector(
                      onTap: _prev,
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: LColors.inkMid),
                    )
                  else
                    const SizedBox(width: 20),
                  const Spacer(),
                  Text(
                    'Test Setup',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        letterSpacing: -0.2, color: LColors.ink),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onReady,
                    style: TextButton.styleFrom(
                      foregroundColor: LColors.inkMid,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text('Skip', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),

            // Step dots
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? LColors.cyan : LColors.inkLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: _pages,
              ),
            ),

            // CTA button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: isLast ? LColors.cyan : LColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: Text(isLast ? "I'm ready — start recording" : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: What you need ────────────────────────────────────────────────────

class _PageSetup extends StatelessWidget {
  const _PageSetup();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      icon: '📦',
      title: 'What you need',
      children: [
        _InfoCard(
          icon: Icons.view_agenda_outlined,
          label: 'Box',
          body: '30 cm (12 in) step or box. Taller = more drop force, '
              'but 30 cm is the clinical standard.',
        ),
        _InfoCard(
          icon: Icons.smartphone_rounded,
          label: 'Phone + tripod (or stable surface)',
          body: '3–4 metres from the athlete, at hip height, aimed straight at the front.',
        ),
        _InfoCard(
          icon: Icons.repeat_rounded,
          label: '3–5 trials per view',
          body: 'Record front first, then rotate 90° for the side. '
              'More trials = more stable averages.',
        ),
        _Tip('Wear fitted clothing so the AI can track your joints clearly.'),
      ],
    );
  }
}

// ── Page 2: The movement ─────────────────────────────────────────────────────

class _PageMovement extends StatelessWidget {
  const _PageMovement();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      icon: '🦵',
      title: 'The Drop Vertical Jump',
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            'The landing pattern — not the jump — is what gets analysed.',
            style: TextStyle(fontSize: 13.5, color: LColors.inkMid, height: 1.5),
          ),
        ),
        const SizedBox(height: 4),
        _Step(n: '1', text: 'Stand on the box with both feet.'),
        _Step(n: '2', text: 'Step off with one foot — like stepping off a curb. Don\'t jump.'),
        _Step(n: '3', text: 'As that foot leaves, bring the other off too. You\'ll be briefly airborne.'),
        _Step(n: '4', text: 'Land with both feet at the same time.'),
        _Step(n: '5', text: 'Immediately jump straight up as high as you can.'),
        _Step(n: '6', text: 'Land again. This is the landing that gets measured.'),
        const SizedBox(height: 12),
        _Tip('Cue: "Step off like a curb, jump up the moment you land."'),
        const SizedBox(height: 8),
        _WarningCard(
          'Do NOT jump off the box — it creates too much force and throws off the measurement.',
        ),
      ],
    );
  }
}

// ── Page 3: Camera setup ─────────────────────────────────────────────────────

class _PageCamera extends StatelessWidget {
  const _PageCamera();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      icon: '📸',
      title: 'Camera setup',
      children: [
        _InfoCard(
          icon: Icons.person_outline_rounded,
          label: 'Front view (view 1)',
          body: 'Athlete faces the camera square — even 15° off-axis affects the valgus reading. '
              'Full body in frame, head to feet.',
        ),
        _InfoCard(
          icon: Icons.rotate_90_degrees_cw_outlined,
          label: 'Side view (view 2)',
          body: 'Rotate the phone (or tripod) 90°. Athlete should face sideways '
              'to the camera. Captures knee flexion depth.',
        ),
        _WarningCard('Don\'t hold the phone by hand — any shake degrades keypoint tracking.'),
        const SizedBox(height: 8),
        _Tip('Same box, same distance, same camera height every session — you\'re tracking trends over time.'),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _PageShell extends StatelessWidget {
  final String icon;
  final String title;
  final List<Widget> children;
  const _PageShell({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                  letterSpacing: -0.5, color: LColors.ink)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String body;
  const _InfoCard({required this.icon, required this.label, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LColors.stroke),
        boxShadow: kCardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: LColors.cyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: LColors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: LColors.ink)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 12.5, color: LColors.inkMid, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: LColors.navy,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(n,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text,
                  style: const TextStyle(fontSize: 13.5, color: LColors.ink, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LColors.cyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LColors.cyan.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, color: LColors.ink, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String text;
  const _WarningCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LColors.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LColors.red.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, color: LColors.ink, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
