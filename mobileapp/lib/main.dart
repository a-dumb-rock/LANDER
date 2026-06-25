import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart'; 
import 'session_detail_screen.dart';
import 'session_manager.dart';

// Global list of available cameras initialized at launch
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Error initializing cameras: $e");
  }
  runApp(const LandrApp());
}

class LandrApp extends StatelessWidget {
  const LandrApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LANDR Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        primaryColor: Colors.amberAccent,
        cardColor: const Color(0xFF141418),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amberAccent,
          surface: Color(0xFF141418),
          background: Color(0xFF0A0A0C),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// --- MAIN NAVIGATION WRAPPER WITH TAB CHANGE CALL-BACKS ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      ActualHomePage(onStartPressed: () => _navigateToTab(1)),    
      const CameraScreen(),      
      ProgressPage(onNavigateToCapture: () => _navigateToTab(1)),      
    ];
  }

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 2) {
        _pages[2] = ProgressPage(
          key: UniqueKey(),
          onNavigateToCapture: () => _navigateToTab(1),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1F1F24), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => _navigateToTab(index),
          selectedItemColor: Colors.amberAccent,
          unselectedItemColor: Colors.grey[600],
          backgroundColor: const Color(0xFF0E0E12),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam_rounded),
              label: 'Capture',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_rounded),
              label: 'Metrics',
            ),
          ],
        ),
      ),
    );
  }
}

// --- TAB 1: PREMIUM HOME HERO PAGE ---
class ActualHomePage extends StatelessWidget {
  final VoidCallback onStartPressed;

  const ActualHomePage({super.key, required this.onStartPressed});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text("PRO", style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            const Text("LANDR • Live Tracking", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0C),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Text('Biomechanical\nScreening', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5, color: Colors.white)),
            const SizedBox(height: 8),
            Text('Real-time computer vision tracking of dynamic valgus patterns.', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
            const SizedBox(height: 32),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111115),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amberAccent.withOpacity(0.15), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.analytics_outlined, color: Colors.amberAccent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ready to Analyze', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          SizedBox(height: 2),
                          Text('Capture raw landing frame data streams', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onStartPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('START NEW SCREENING', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1F1F26), width: 1),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(0xFF1E1E24),
                      child: Icon(Icons.bolt, color: Colors.amberAccent, size: 20),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lighting Optimization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                          SizedBox(height: 2),
                          Text('High contrast environments minimize dropped coordinates.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TAB 2: TECH CAPTURE ENGINE SCREEN ---
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isProcessing = false;
  String _resultText = "Position athlete inside guidelines to start calculation loop";
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) {
      _controller = CameraController(cameras[0], ResolutionPreset.high);
      _controller!.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      setState(() {
        _isProcessing = true;
        _resultText = "Uploading file stream to biomechanics server...";
      });
      await _uploadVideo(File(video.path));
    } catch (e) {
      setState(() {
        _resultText = "Gallery file reading issue: $e";
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) {
      try {
        final file = await _controller!.stopVideoRecording();
        setState(() {
          _isRecording = false;
          _isProcessing = true;
          _resultText = "Processing recorded segment data structures...";
        });
        await _uploadVideo(File(file.path));
      } catch (e) {
        setState(() {
          _isRecording = false;
          _isProcessing = false;
          _resultText = "Capture runtime exception: $e";
        });
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _resultText = "WRITING INPUT VIDEO TO CACHE BUFFER...";
        });
      } catch (e) {
        setState(() {
          _resultText = "Camera sensor is currently busy.";
        });
      }
    }
  }

  Future<void> _uploadVideo(File videoFile) async {
    final url = Uri.parse("http://192.168.0.162:8000/analyze-landing");
    try {
      final request = http.MultipartRequest("POST", url)
        ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));
      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(responseData);
        setState(() {
          _resultText = "Matrix telemetry logged.";
          SessionData.addSessionFromBackend(data);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ SESSION COMPUTE COMPLETED'), backgroundColor: Color(0xFF00E676)),
        );
      } else {
        setState(() { _resultText = "Error context code: ${response.statusCode}"; });
      }
    } catch (e) {
      setState(() { _resultText = "Link offline. Check host connection config."; });
    } finally {
      setState(() { _isProcessing = false; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0C),
        body: Center(child: CircularProgressIndicator(color: Colors.amberAccent)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        title: const Text("CAPTURE TERMINAL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)), 
        backgroundColor: const Color(0xFF0A0A0C), 
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(child: CameraPreview(_controller!)),
                    Positioned.fill(child: CustomPaint(painter: CameraGuidePainter())),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_resultText.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _isRecording ? const Color(0xFFFF455B) : Colors.grey[400], letterSpacing: 0.5, height: 1.4)),
                  const SizedBox(height: 20),
                  _isProcessing
                      ? const CircularProgressIndicator(color: Colors.amberAccent)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: _pickVideoFromGallery,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: const Color(0xFF141418), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF26262F))),
                                child: const Icon(Icons.collections_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                            const SizedBox(width: 32),
                            GestureDetector(
                              onTap: _toggleRecording,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _isRecording ? const Color(0xFFFF455B) : Colors.amberAccent, width: 2)),
                                child: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: _isRecording ? const Color(0xFFFF455B) : Colors.white,
                                  child: Icon(_isRecording ? Icons.stop_rounded : Icons.videocam_rounded, color: _isRecording ? Colors.white : Colors.black, size: 28),
                                ),
                              ),
                            ),
                          ],
                        )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class CameraGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.amberAccent..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final double length = 25.0; 
    final double pad = 30.0; 
    
    final topY = pad * 1.5; final botY = size.height - pad * 2;
    final leftX = pad; final rightX = size.width - pad;

    canvas.drawPath(Path()..moveTo(leftX, topY + length)..lineTo(leftX, topY)..lineTo(leftX + length, topY), paint);
    canvas.drawPath(Path()..moveTo(rightX, topY + length)..lineTo(rightX, topY)..lineTo(rightX - length, topY), paint);
    canvas.drawPath(Path()..moveTo(leftX, botY - length)..lineTo(leftX, botY)..lineTo(leftX + length, botY), paint);
    canvas.drawPath(Path()..moveTo(rightX, botY - length)..lineTo(rightX, botY)..lineTo(rightX - length, botY), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- TAB 3: CYBER DETAILED PERFORMANCE RESULTS ---
class ProgressPage extends StatefulWidget {
  final VoidCallback onNavigateToCapture;
  const ProgressPage({super.key, required this.onNavigateToCapture});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  @override
  Widget build(BuildContext context) {
    if (SessionData.history.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0C),
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF111115), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1F1F26))),
                child: const Icon(Icons.analytics_outlined, color: Colors.grey, size: 40),
              ),
              const SizedBox(height: 24),
              const Text("NO TRACKING TRACKS SAVED", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1, color: Colors.white)),
              const SizedBox(height: 8),
              Text("Run telemetry pipelines through the engine to map displacement parameters here.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.4)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: widget.onNavigateToCapture,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF141418),
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amberAccent, width: 1),
                  minimumSize: const Size(180, 45),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("LAUNCH TERMINAL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    final latest = SessionData.history.last;
    bool isHighRisk = latest.riskFactor.toUpperCase().contains("HIGH");
    bool isModRisk = latest.riskFactor.toUpperCase().contains("MODERATE");
    Color riskColor = isHighRisk ? const Color(0xFFFF455B) : isModRisk ? const Color(0xFFFF9100) : const Color(0xFF00E676);

    List<FlSpot> spots = SessionData.history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.maxValgus)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        title: Text(latest.title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)), 
        backgroundColor: const Color(0xFF0A0A0C), 
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF111115),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F1F26)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF1C1C24),
                  child: Icon(isHighRisk ? Icons.gpp_bad_rounded : Icons.verified_user_rounded, color: riskColor, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(latest.riskFactor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: riskColor, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text(latest.coachingCue, style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.4)),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF111115), 
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F1F26)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("VALGUS DISPLAY PROFILE", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text("HISTORICAL DISPLACEMENT MONITOR (${latest.maxValgus.toStringAsFixed(1)}°)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 32),
                SizedBox(
                  height: 120,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: riskColor,
                          barWidth: 4,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: index == spots.length - 1 ? 5 : 3, color: index == spots.length - 1 ? riskColor : Colors.white, strokeWidth: 2, strokeColor: const Color(0xFF0A0A0C)),
                          ),
                        )
                      ]
                    )
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildHUDCard("PEAK VALGUS DEG", "${latest.maxValgus.toStringAsFixed(1)}°", latest.maxValgus >= 10.0),
              _buildHUDCard("ASYM INDEX RATIO", "${(latest.asymmetryIndex * 100).toStringAsFixed(1)}%", latest.asymmetryIndex >= 0.10),
            ],
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111115),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F1F26)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("COMPARATIVE RUN ENGINE DISPLACEMENT LOGS", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: SessionData.history.map((s) => _buildOriginalCustomBar(s.title.replaceAll("Landing Session #", "S-"), s.maxValgus)).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text("SESSIONS HISTORY RECORDED TRACKS", style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: SessionData.history.length,
            itemBuilder: (context, index) {
              final session = SessionData.history.reversed.toList()[index];
              bool itemHigh = session.riskFactor.toUpperCase().contains("HIGH");
              bool itemMod = session.riskFactor.toUpperCase().contains("MODERATE");
              Color itemColor = itemHigh ? const Color(0xFFFF455B) : itemMod ? const Color(0xFFFF9100) : const Color(0xFF00E676);

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF111115), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1C1C22))),
                child: ListTile(
                  leading: Icon(Icons.bar_chart_rounded, color: itemColor, size: 20),
                  title: Text(session.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  subtitle: Text('${session.date} • ${session.maxValgus.toStringAsFixed(1)}°', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                        onPressed: () {
                          setState(() {
                            SessionData.deleteSession(session);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('REMOVED ${session.title.toUpperCase()}'), 
                              backgroundColor: const Color(0xFF141418),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SessionDetailScreen(
                          sessionTitle: session.title,
                          date: session.date,
                          riskFactor: session.riskFactor,
                          maxValgus: session.maxValgus,
                          coachingCue: session.coachingCue,
                          asymmetry: session.asymmetryIndex,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHUDCard(String title, String value, bool warning) {
    Color indicator = warning ? const Color(0xFFFF455B) : const Color(0xFF00E676);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111115),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F1F26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: indicator, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(warning ? "CRIT RISK" : "OPTIMAL", style: TextStyle(color: indicator, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildOriginalCustomBar(String label, double score) {
    Color barColor = const Color(0xFF00E676);      
    if (score >= 10.0) {
      barColor = const Color(0xFFFF455B);          
    } else if (score >= 5.0) {
      barColor = const Color(0xFFFF9100);       
    }

    double clampedScore = score.clamp(0.0, 20.0);
    double visualHeight = (clampedScore / 20.0) * 60.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          "${score.toStringAsFixed(1)}°", 
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)
        ),
        const SizedBox(height: 4),
        Container(
          width: 20,
          height: visualHeight, 
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 9)),
      ],
    );
  }
}