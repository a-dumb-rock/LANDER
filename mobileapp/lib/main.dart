import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'config.dart';
import 'session_detail_screen.dart';
import 'session_manager.dart';
import 'skeleton.dart';
import 'theme.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Error initializing cameras: $e");
  }
  runApp(const LandrApp());
}

class LandrApp extends StatelessWidget {
  const LandrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LANDR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: LColors.bg,
        primaryColor: LColors.navy,
        cardColor: LColors.surface,
        colorScheme: const ColorScheme.light(
          primary: LColors.navy,
          secondary: LColors.cyan,
          surface: LColors.surface,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

/// "N days ago" label from a "Month D, YYYY" string.
String lastScreenAgo(String dateLabel) {
  const months = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  try {
    final parts = dateLabel.replaceAll(',', '').split(' ');
    final m = months.indexOf(parts[0]);
    final d = int.parse(parts[1]);
    final y = int.parse(parts[2]);
    final then = DateTime(y, m, d);
    final days = DateTime.now().difference(then).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  } catch (_) {
    return dateLabel;
  }
}

// ── MAIN NAVIGATION ──────────────────────────────────────────────────────────

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  void _go(int index) => setState(() => _currentIndex = index);

  void _openAthlete(Athlete a) {
    RosterData.select(a.id);
    _go(3);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RosterPage(onNewScreening: () => _go(2), onOpenAthlete: _openAthlete),
      const TrendsPage(),
      CameraScreen(onAnalysed: () => _go(3)),
      ResultsPage(onCapture: () => _go(2)),
      const InfoPage(),
    ];

    return Scaffold(
      backgroundColor: LColors.bg,
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: _BottomNav(currentIndex: _currentIndex, onTap: _go),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final selected = i == currentIndex;
      return Expanded(
        child: GestureDetector(
          onTap: () => onTap(i),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: selected ? LColors.ink : LColors.inkLow),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 9.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? LColors.ink : LColors.inkLow)),
            ],
          ),
        ),
      );
    }

    final screenSelected = currentIndex == 2;

    return Container(
      decoration: const BoxDecoration(
        color: LColors.surface,
        border: Border(top: BorderSide(color: LColors.stroke)),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              item(0, Icons.home_outlined, 'Roster'),
              item(1, Icons.show_chart_rounded, 'Trends'),
              // center Screen
              Expanded(
                child: GestureDetector(
                  onTap: () => onTap(2),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: screenSelected ? LColors.cyan : LColors.navy,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: (screenSelected ? LColors.cyan : LColors.navy).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(height: 2),
                      Text('Screen', style: TextStyle(fontSize: 9.5, fontWeight: screenSelected ? FontWeight.w700 : FontWeight.w500, color: screenSelected ? LColors.ink : LColors.inkLow)),
                    ],
                  ),
                ),
              ),
              item(3, Icons.bar_chart_rounded, 'Result'),
              item(4, Icons.info_outline_rounded, 'Info'),
            ],
          ),
        ),
      ),
    );
  }
}

// ── TAB 1: ROSTER ─────────────────────────────────────────────────────────────

class RosterPage extends StatelessWidget {
  final VoidCallback onNewScreening;
  final ValueChanged<Athlete> onOpenAthlete;
  const RosterPage({super.key, required this.onNewScreening, required this.onOpenAthlete});

  @override
  Widget build(BuildContext context) {
    final athletes = RosterData.athletes;
    final highCount = athletes.where((a) => a.screened && a.latest!.riskFactor.toUpperCase().contains('HIGH')).length;

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        children: [
          Row(
            children: [
              const LandrWordmark(size: 22),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: LColors.surface, shape: BoxShape.circle, border: Border.all(color: LColors.stroke), boxShadow: kCardShadow),
                child: const Icon(Icons.settings_outlined, size: 17, color: LColors.inkMid),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Text('Landing\nscreening',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -1, color: LColors.ink)),
          const SizedBox(height: 12),
          const Text(
            'Catch the ACL-injury pattern — knees caving under fatigue — from one phone clip.',
            style: TextStyle(fontSize: 13.5, color: LColors.inkMid, height: 1.5),
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: 'New screening', icon: Icons.add_rounded, onTap: onNewScreening),
          const SizedBox(height: 26),
          SectionLabel('ATHLETES', trailing: Text('${athletes.length}', style: const TextStyle(fontSize: 12, color: LColors.inkLow, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          LCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < athletes.length; i++) ...[
                  _AthleteRow(athlete: athletes[i], onTap: () => onOpenAthlete(athletes[i])),
                  if (i != athletes.length - 1) const Divider(height: 1, color: LColors.stroke, indent: 66),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel('THIS SQUAD'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _SquadStat(value: '${athletes.length}', label: 'Athletes')),
              const SizedBox(width: 10),
              Expanded(child: _SquadStat(value: '${athletes.where((a) => a.screened).length}', label: 'Screened')),
              const SizedBox(width: 10),
              Expanded(child: _SquadStat(value: '$highCount', label: 'High risk', color: highCount > 0 ? LColors.red : LColors.ink)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SquadStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _SquadStat({required this.value, required this.label, this.color = LColors.ink});
  @override
  Widget build(BuildContext context) {
    return LCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: LColors.inkMid)),
        ],
      ),
    );
  }
}

class _AthleteRow extends StatelessWidget {
  final Athlete athlete;
  final VoidCallback onTap;
  const _AthleteRow({required this.athlete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final latest = athlete.latest;
    final screened = athlete.screened;
    final statusColor = !screened ? LColors.slate : LColors.risk(latest!.riskFactor);
    final statusText = !screened ? 'NO SCREEN' : latest!.riskFactor.split(' ').first.toUpperCase();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Monogram(athlete.monogram, athlete.accent, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14.5, color: LColors.ink),
                      children: [
                        TextSpan(text: athlete.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: '  '),
                        TextSpan(text: athlete.sport, style: const TextStyle(color: LColors.inkMid, fontWeight: FontWeight.w400, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    screened ? '${athlete.ageCode} · Last screen · ${lastScreenAgo(latest!.date)}' : '${athlete.ageCode} · Not screened yet',
                    style: const TextStyle(fontSize: 11.5, color: LColors.inkLow),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (screened)
              SizedBox(width: 42, height: 22, child: CustomPaint(painter: _SparkPainter(latest!.valgusSeries(24), statusColor))),
            const SizedBox(width: 8),
            StatusPill(statusText, statusColor),
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  _SparkPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final mn = data.reduce((a, b) => a < b ? a : b);
    final mx = data.reduce((a, b) => a > b ? a : b);
    final range = (mx - mn).abs() < 0.001 ? 1.0 : (mx - mn);
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - ((data[i] - mn) / range) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.data != data || old.color != color;
}

// ── TAB 2: TRENDS ─────────────────────────────────────────────────────────────

class TrendsPage extends StatelessWidget {
  const TrendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final athletes = RosterData.athletes.where((a) => a.screened).toList();

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('Trends', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: LColors.ink)),
          const SizedBox(height: 6),
          const Text('Peak knee valgus across each athlete’s recent screenings.',
              style: TextStyle(fontSize: 13, color: LColors.inkMid, height: 1.5)),
          const SizedBox(height: 22),
          if (athletes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('No screenings yet.', style: TextStyle(color: LColors.inkMid))),
            )
          else
            ...athletes.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: LCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Monogram(a.monogram, a.accent, size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: LColors.ink)),
                                  Text('${a.sessions.length} screenings · peak ${a.latest!.maxValgus.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 11, color: LColors.inkMid)),
                                ],
                              ),
                            ),
                            StatusPill(a.latest!.riskFactor.split(' ').first.toUpperCase(), LColors.risk(a.latest!.riskFactor)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(height: 90, child: _MiniTrend(sessions: a.sessions, color: LColors.risk(a.latest!.riskFactor))),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _MiniTrend extends StatelessWidget {
  final List<JumpSession> sessions;
  final Color color;
  const _MiniTrend({required this.sessions, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = sessions.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.maxValgus)).toList();
    if (spots.length < 2) {
      return const Center(child: Text('Need 2+ screenings for a trend', style: TextStyle(fontSize: 11, color: LColors.inkLow)));
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: LColors.stroke, strokeWidth: 1)),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, reservedSize: 16, getTitlesWidget: (v, m) {
            final i = v.toInt();
            if (i < 0 || i >= sessions.length) return const SizedBox();
            return Text('S${i + 1}', style: const TextStyle(color: LColors.inkLow, fontSize: 8));
          })),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 5, reservedSize: 24, getTitlesWidget: (v, m) => Text('${v.toInt()}°', style: const TextStyle(color: LColors.inkLow, fontSize: 8)))),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true, color: color, barWidth: 2.5, isStrokeCapRound: true,
            belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withOpacity(0.16), color.withOpacity(0.0)])),
            dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: i == spots.length - 1 ? 4 : 2.5, color: color, strokeWidth: 0)),
          ),
        ],
      ),
    );
  }
}

// ── TAB 3: SCREEN (CAPTURE) — Two-view: front then side ──────────────────────

/// Which step of the two-view capture flow we're in.
enum _CaptureStep { front, side, uploading, done }

class CameraScreen extends StatefulWidget {
  final VoidCallback onAnalysed;
  const CameraScreen({super.key, required this.onAnalysed});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isRecording = false;
  bool _isSwitching = false;
  String _statusText = '';
  final ImagePicker _picker = ImagePicker();

  _CaptureStep _step = _CaptureStep.front;
  File? _frontVideo;   // set after step 1
  File? _sideVideo;    // set after step 2

  @override
  void initState() {
    super.initState();
    _initCamera(_cameraIndex);
  }

  Future<void> _initCamera(int index) async {
    if (cameras.isEmpty) return;
    final controller = CameraController(cameras[index], ResolutionPreset.high, enableAudio: false);
    try {
      await controller.initialize();
      if (!mounted) return;
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _isSwitching = false;
      });
    } catch (e) {
      setState(() {
        _statusText = 'Camera init error';
        _isSwitching = false;
      });
    }
  }

  Future<void> _flipCamera() async {
    if (cameras.length < 2 || _isRecording || _isSwitching) return;
    setState(() => _isSwitching = true);
    await _initCamera((_cameraIndex + 1) % cameras.length);
  }

  /// Pick from gallery for the current step.
  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      await _handleCapturedFile(File(video.path));
    } catch (e) {
      setState(() => _statusText = 'Could not read video from gallery.');
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) {
      try {
        final file = await _controller!.stopVideoRecording();
        setState(() => _isRecording = false);
        await _handleCapturedFile(File(file.path));
      } catch (e) {
        setState(() {
          _isRecording = false;
          _statusText = 'Recording error';
        });
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _statusText = _step == _CaptureStep.front
              ? 'Recording FRONT — stop when landing is done.'
              : 'Recording SIDE — stop when landing is done.';
        });
      } catch (e) {
        setState(() => _statusText = 'Could not start recording.');
      }
    }
  }

  /// Called when a video is captured or picked; advances the state machine.
  Future<void> _handleCapturedFile(File file) async {
    if (_step == _CaptureStep.front) {
      setState(() {
        _frontVideo = file;
        _step = _CaptureStep.side;
        _statusText = 'Front clip saved — now record the SIDE view.';
      });
    } else if (_step == _CaptureStep.side) {
      setState(() {
        _sideVideo = file;
        _step = _CaptureStep.uploading;
        _statusText = 'Uploading both clips…';
      });
      await _uploadBothVideos(_frontVideo!, _sideVideo!);
    }
  }

  void _resetCapture() {
    setState(() {
      _step = _CaptureStep.front;
      _frontVideo = null;
      _sideVideo = null;
      _statusText = '';
    });
  }

  Future<void> _uploadBothVideos(File front, File side) async {
    final url = Uri.parse("$kServerBaseUrl/analyze-landing-two-view");
    try {
      final request = http.MultipartRequest("POST", url)
        ..files.add(await http.MultipartFile.fromPath('front', front.path))
        ..files.add(await http.MultipartFile.fromPath('side', side.path));
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(responseData);
        if (!mounted) return;
        setState(() {
          _statusText = 'Analysis complete.';
          _step = _CaptureStep.done;
          RosterData.addSessionFromBackend(data);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Two-view analysis ready for ${RosterData.selected.firstName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          backgroundColor: LColors.navy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        widget.onAnalysed();
      } else {
        setState(() {
          _statusText = 'Server error (${response.statusCode}).';
          _step = _CaptureStep.front;
        });
      }
    } catch (e) {
      setState(() {
        _statusText = 'Cannot reach server. Check IP / network.';
        _step = _CaptureStep.front;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _previewCover() {
    final size = _controller!.value.previewSize;
    if (size == null) return CameraPreview(_controller!);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: size.height, height: size.width, child: CameraPreview(_controller!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller != null && _controller!.value.isInitialized && !_isSwitching;
    final athlete = RosterData.selected;
    final isFront = _step == _CaptureStep.front;
    final isUploading = _step == _CaptureStep.uploading;
    final viewLabel = isFront ? 'FRONT VIEW' : 'SIDE VIEW';
    final stepLabel = isFront ? 'Step 1 of 2 — Front' : 'Step 2 of 2 — Side';

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              const Text('DROP-VERTICAL JUMP', style: TextStyle(fontSize: 10.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(color: LColors.navy, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: athlete.accent, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    Text(athlete.firstName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Step header
          Row(
            children: [
              Expanded(
                child: Text(
                  isFront ? 'Record front view' : 'Now record side view',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: LColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(stepLabel, style: const TextStyle(fontSize: 12, color: LColors.inkMid, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 14),

          // Step progress dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepDot(active: true, done: !isFront, label: 'Front'),
              Container(width: 28, height: 2, color: isFront ? LColors.stroke : LColors.cyan),
              _StepDot(active: !isFront, done: false, label: 'Side'),
            ],
          ),
          const SizedBox(height: 16),

          // Camera preview card
          AspectRatio(
            aspectRatio: 0.82,
            child: Container(
              decoration: BoxDecoration(
                color: LColors.panel,
                borderRadius: BorderRadius.circular(20),
                boxShadow: kCardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ready)
                      _previewCover()
                    else
                      Center(
                        child: _isSwitching
                            ? const CircularProgressIndicator(color: LColors.cyan, strokeWidth: 2)
                            : FractionallySizedBox(
                                widthFactor: 0.5,
                                child: CustomPaint(painter: SkeletonPainter(Pose.landing(t: 0, severity: 0, arms: 0.2), color: LColors.cyan, stroke: 3)),
                              ),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Color(0x00000000), Color(0x55000000)], stops: [0, 0.3, 1]),
                      ),
                    ),
                    Positioned.fill(child: CustomPaint(painter: _ReticlePainter(_isRecording))),
                    // View label pill
                    Positioned(
                      top: 14, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: LColors.cyan.withOpacity(0.6)),
                          ),
                          child: Text(viewLabel, style: const TextStyle(color: LColors.cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                        ),
                      ),
                    ),
                    // Front-clip-saved badge on step 2
                    if (!isFront && !isUploading)
                      Positioned(
                        top: 14, right: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: LColors.green.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, color: Colors.white, size: 11),
                              SizedBox(width: 4),
                              Text('FRONT ✓', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                            ],
                          ),
                        ),
                      ),
                    if (_isRecording) const Positioned(top: 14, left: 14, child: _RecBadge()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Checklist — changes per step
          LCard(
            child: Column(
              children: isFront ? const [
                _CheckRow('Whole body in frame, head to feet'),
                SizedBox(height: 12),
                _CheckRow('Athlete facing the camera, knees visible'),
                SizedBox(height: 12),
                _CheckRow('Phone steady at hip height'),
                SizedBox(height: 12),
                _CheckRow('One clean rep, 3–5 seconds'),
              ] : const [
                _CheckRow('Move phone 90° to the athlete\'s side'),
                SizedBox(height: 12),
                _CheckRow('Whole body in frame, head to feet'),
                SizedBox(height: 12),
                _CheckRow('Athlete\'s side profile fully visible'),
                SizedBox(height: 12),
                _CheckRow('Same jump direction as front clip'),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (isUploading)
            Column(
              children: [
                const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: LColors.navy, strokeWidth: 2.5)),
                const SizedBox(height: 12),
                Text(_statusText.isEmpty ? 'Analyzing both views…' : _statusText, style: const TextStyle(color: LColors.inkMid, fontSize: 12)),
              ],
            )
          else ...[
            Row(
              children: [
                _OutlineButton(icon: Icons.photo_library_outlined, label: 'Upload clip', onTap: _pickVideoFromGallery),
                const SizedBox(width: 12),
                if (cameras.length > 1)
                  _OutlineButton(icon: Icons.cameraswitch_outlined, label: 'Flip', onTap: _isRecording ? null : _flipCamera),
              ],
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: ready ? _toggleRecording : null,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: _isRecording ? LColors.red : LColors.navy,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 6))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 9),
                    Text(
                      _isRecording ? 'Stop recording' : (isFront ? 'Record front view' : 'Record side view'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ],
                ),
              ),
            ),
            if (!isFront) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _resetCapture,
                child: const Center(
                  child: Text('← Retake front clip', style: TextStyle(color: LColors.inkMid, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (_statusText.isNotEmpty && !_isRecording) ...[
              const SizedBox(height: 10),
              Center(child: Text(_statusText, style: const TextStyle(color: LColors.inkMid, fontSize: 11.5))),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Step progress dot ────────────────────────────────────────────────────────
class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;
  const _StepDot({required this.active, required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = (active || done) ? LColors.cyan : LColors.stroke;
    return Column(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
          child: done
              ? const Icon(Icons.check_rounded, size: 14, color: LColors.cyan)
              : Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: active ? LColors.cyan : Colors.transparent, shape: BoxShape.circle))),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _OutlineButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: LColors.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: LColors.stroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: disabled ? LColors.inkLow : LColors.ink),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: disabled ? LColors.inkLow : LColors.ink, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String text;
  const _CheckRow(this.text);
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: LColors.green.withOpacity(0.14), borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.check_rounded, color: LColors.green, size: 13),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: LColors.ink, fontSize: 13, fontWeight: FontWeight.w500))),
      ],
    );
  }
}

class _RecBadge extends StatelessWidget {
  const _RecBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: LColors.red, borderRadius: BorderRadius.circular(8)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 7),
          SizedBox(width: 6),
          Text('REC', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final bool recording;
  _ReticlePainter(this.recording);
  @override
  void paint(Canvas canvas, Size size) {
    final color = recording ? LColors.red : LColors.cyan;
    final paint = Paint()..color = color.withOpacity(0.9)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    const len = 26.0, pad = 16.0;
    final t = pad + 6, b = size.height - pad, l = pad, rr = size.width - pad;
    canvas.drawPath(Path()..moveTo(l, t + len)..lineTo(l, t)..lineTo(l + len, t), paint);
    canvas.drawPath(Path()..moveTo(rr - len, t)..lineTo(rr, t)..lineTo(rr, t + len), paint);
    canvas.drawPath(Path()..moveTo(l, b - len)..lineTo(l, b)..lineTo(l + len, b), paint);
    canvas.drawPath(Path()..moveTo(rr - len, b)..lineTo(rr, b)..lineTo(rr, b - len), paint);
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) => old.recording != recording;
}

// ── TAB 4: RESULT ─────────────────────────────────────────────────────────────

class ResultsPage extends StatefulWidget {
  final VoidCallback onCapture;
  const ResultsPage({super.key, required this.onCapture});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  @override
  Widget build(BuildContext context) {
    final athlete = RosterData.selected;
    final latest = athlete.latest;

    if (latest == null) return _EmptyResults(athlete: athlete, onCapture: widget.onCapture);

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              const Text('RESULT', style: TextStyle(fontSize: 10.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
              const SizedBox(width: 8),
              Text('· ${athlete.fullName.toUpperCase()}', style: const TextStyle(fontSize: 10.5, color: LColors.inkLow, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
              const Spacer(),
              StatusPill(latest.riskFactor.split(' ').first.toUpperCase(), LColors.risk(latest.riskFactor)),
            ],
          ),
          const SizedBox(height: 16),
          SessionReport(session: latest, athlete: athlete),
          if (athlete.sessions.length > 1) ...[
            const SizedBox(height: 24),
            SectionLabel('SESSION HISTORY', trailing: Text('${athlete.sessions.length} total', style: const TextStyle(fontSize: 10, color: LColors.inkLow))),
            const SizedBox(height: 12),
            ...athlete.sessions.reversed.map((s) => _HistoryTile(
                  session: s,
                  onDelete: () => setState(() => RosterData.deleteSession(athlete, s)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SessionDetailScreen(session: s, athlete: athlete))),
                )),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final JumpSession session;
  final VoidCallback onDelete, onTap;
  const _HistoryTile({required this.session, required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sc = LColors.risk(session.riskFactor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(Icons.bar_chart_rounded, color: sc, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(session.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: LColors.ink))),
                    const SizedBox(width: 7),
                    if (session.isDemo) const OutlineChip('DEMO')
                    else const OutlineChip('REAL', color: LColors.cyan),
                  ]),
                  const SizedBox(height: 3),
                  Text('${session.date} · ${session.maxValgus.toStringAsFixed(1)}° · LESS ${session.lessScore}', style: const TextStyle(color: LColors.inkMid, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(onTap: onDelete, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, color: LColors.inkLow, size: 18))),
            const Icon(Icons.chevron_right_rounded, color: LColors.inkLow, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  final Athlete athlete;
  final VoidCallback onCapture;
  const _EmptyResults({required this.athlete, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
        child: Column(
          children: [
            Row(children: [const Text('RESULT', style: TextStyle(fontSize: 10.5, color: LColors.inkMid, fontWeight: FontWeight.w700, letterSpacing: 1.4)), const Spacer(), Text(athlete.fullName, style: const TextStyle(color: LColors.inkMid, fontSize: 12))]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: LColors.surface, shape: BoxShape.circle, border: Border.all(color: LColors.stroke), boxShadow: kCardShadow),
              child: const Icon(Icons.query_stats_rounded, color: LColors.navy, size: 40),
            ),
            const SizedBox(height: 26),
            Text('${athlete.firstName} isn’t screened yet', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: LColors.ink, letterSpacing: -0.5)),
            const SizedBox(height: 10),
            const Text('Record or upload a landing video to run the first ACL risk analysis.', textAlign: TextAlign.center, style: TextStyle(color: LColors.inkMid, fontSize: 13, height: 1.55)),
            const SizedBox(height: 28),
            SizedBox(width: 220, child: PrimaryButton(label: 'Start screening', icon: Icons.videocam_rounded, onTap: onCapture)),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

// ── TAB 5: INFO ───────────────────────────────────────────────────────────────

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const LandrWordmark(size: 26),
          const SizedBox(height: 16),
          const Text('About LANDR', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: LColors.ink)),
          const SizedBox(height: 8),
          const Text(
            'LANDR screens athletes for the dynamic knee-valgus pattern linked to ACL injury — from a single phone clip of a drop-vertical jump. It is fatigue-aware: the same landing is compared fresh vs fatigued to estimate how much mechanics decay under load.',
            style: TextStyle(fontSize: 13.5, color: LColors.inkMid, height: 1.55),
          ),
          const SizedBox(height: 20),
          SectionLabel('HOW IT WORKS'),
          const SizedBox(height: 10),
          const _InfoStep(n: '1', title: 'Capture', body: 'Film one clean drop-vertical jump, front view, whole body in frame.'),
          const _InfoStep(n: '2', title: 'Analyse', body: 'Pose estimation measures knee valgus, flexion, asymmetry and LESS error patterns.'),
          const _InfoStep(n: '3', title: 'Screen', body: 'A composite ACL-risk score and fatigue-vulnerability estimate, with coaching cues.'),
          const SizedBox(height: 20),
          LCard(
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: LColors.inkMid, size: 16),
                SizedBox(width: 10),
                Expanded(child: Text('Decision-support only. Always keep a qualified clinician in the loop.', style: TextStyle(color: LColors.inkMid, fontSize: 12, height: 1.4))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final String n, title, body;
  const _InfoStep({required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: LColors.navy, borderRadius: BorderRadius.circular(9)),
              child: Center(child: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: LColors.ink)),
                  const SizedBox(height: 3),
                  Text(body, style: const TextStyle(fontSize: 12, color: LColors.inkMid, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
