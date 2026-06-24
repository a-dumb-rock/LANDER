import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'session_detail_screen.dart';
import 'session_manager.dart';

// Global list of available cameras
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
      theme: ThemeData.dark(),
      home: const MainNavigationScreen(),
    );
  }
}

// --- MAIN NAVIGATION WRAPPER ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const ActualHomePage(),    // Tab 1: Dashboard
    const CameraScreen(),      // Tab 2: Live Camera Analyzer
    const ProgressPage(),      // Tab 3: Combined Stats & History
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
  currentIndex: _currentIndex,
  onTap: (index) {
    setState(() {
      _currentIndex = index;
      
      // TRICK FLUTTER TO RE-RENDER: By re-instantiating or forcing a lifecycle state 
      // check here, the newly selected tab will read the fresh static list items!
      if (index == 2) {
        // We are selecting the Progress tab, force everything to pull the current data
        _pages[2] = ProgressPage(key: UniqueKey());
      }
    });
  },
  selectedItemColor: Colors.blue,
  unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Progress',
          ),
        ],
      ),
    );
  }
}

// --- TAB 1: ACTUAL HOME PAGE ---
class ActualHomePage extends StatelessWidget {
  const ActualHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("LANDR Home")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to LANDR',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ready to analyze your jump mechanics?',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Card(
              color: Colors.blue.withOpacity(0.1),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.blue, size: 40),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quick Tip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Keep your full lower body inside the camera frame during video recording.', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- TAB 2: CAMERA SCREEN ---
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isProcessing = false;
  String _resultText = "Record a jump landing or select a video file";
  Color _statusColor = Colors.grey;
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
        _resultText = "Uploading selected gallery video to biomechanics backend...";
      });

      await _uploadVideo(File(video.path));
    } catch (e) {
      setState(() {
        _resultText = "Error picking video file from gallery: $e";
        _statusColor = Colors.red;
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
          _resultText = "Uploading and calculating biomechanics...";
        });
        await _uploadVideo(File(file.path));
      } catch (e) {
        setState(() {
          _isRecording = false;
          _isProcessing = false;
          _resultText = "Recording error: $e. Try uploading from gallery instead.";
          _statusColor = Colors.red;
        });
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _resultText = "Recording clip...";
        });
      } catch (e) {
        setState(() {
          _resultText = "Failed to start recording. Emulator camera busy.";
          _statusColor = Colors.red;
        });
      }
    }
  }

  Future<void> _uploadVideo(File videoFile) async {
    final String serverIp = "192.168.0.162"; 
    final url = Uri.parse("http://$serverIp:8000/analyze-landing");

    try {
      final request = http.MultipartRequest("POST", url)
        ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(responseData);
        print("--- BACKEND RESPONSE RECEIVED SUCCESSFULLY: $data ---");
        
        setState(() {
          _resultText = "Analysis Complete:\n${data.toString()}";
          _statusColor = Colors.green;
          
          // DYNAMIC FEED: Injecting real Python json metrics right here!
          SessionData.addSessionFromBackend(data);
        });

        // UI Toast Notification to inform the user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📊 New ACL Risk Analysis Added to Logs!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _resultText = "Server Error: ${response.statusCode}";
          _statusColor = Colors.red;
        });
      }
    } catch (e) {
      setState(() {
        _resultText = "Failed to connect to backend server.\nCheck your IP address config.";
        _statusColor = Colors.red;
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("LANDR Analyzer")),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: CameraPreview(_controller!),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: _statusColor.withOpacity(0.15),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _isProcessing ? "Processing..." : "Analysis Status",
                      style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _resultText.contains("Analysis Complete:") 
                          ? "📊 Jump Landing Analyzed Successfully!\n\nMetrics processed and evaluated via open-source CV framework.\n\nGo to the 'Progress' tab to view charts."
                          : _resultText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: _isProcessing
                ? const CircularProgressIndicator()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        key: const Key("galleryBtn"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: _pickVideoFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text("Gallery", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 24),
                      ElevatedButton.icon(
                        key: const Key("recordBtn"),
                        style: ElevatedButton.styleFrom(backgroundColor: _isRecording ? Colors.red : Colors.blue),
                        onPressed: _toggleRecording,
                        icon: Icon(_isRecording ? Icons.stop : Icons.videocam),
                        label: Text(
                          _isRecording ? "Stop" : "Record", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ],
                  ),
          )
        ],
      ),
    );
  }
}

// --- TAB 3: PROGRESS PAGE ---
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  @override
  Widget build(BuildContext context) {
    List<JumpSession> graphSessions = SessionData.history.length > 5 
        ? SessionData.history.sublist(SessionData.history.length - 5)
        : SessionData.history;

    List<JumpSession> logSessions = SessionData.history.reversed.toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Your Progress")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.blue, size: 28),
              SizedBox(width: 8),
              Text('Performance Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Stability Trend (Last 5 Jumps)",
                  style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: graphSessions.map((session) {
                      String shortLabel = "J${session.title.split('#').last}"; 
                      return _buildBar(shortLabel, session.maxValgus);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          const Row(
            children: [
              Icon(Icons.history, color: Colors.purple, size: 28),
              SizedBox(width: 8),
              Text('Jump History Log', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logSessions.length,
            itemBuilder: (context, index) {
              final session = logSessions[index];
              return ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded, 
                  color: session.riskFactor.contains("HIGH") 
                      ? Colors.redAccent 
                      : session.riskFactor.contains("MODERATE") 
                          ? Colors.orangeAccent 
                          : Colors.greenAccent
                ),
                title: Text(session.title),
                subtitle: Text('${session.date} • ${session.riskFactor} (${session.maxValgus.toStringAsFixed(1)}°)'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
              );
            },
          ),
        ],
      ),
    );
  }

Widget _buildBar(String label, double score) {
  // 1. Color code based on knee valgus angle severity thresholds
  Color barColor = Colors.greenAccent;      
  if (score >= 10.0) {
    barColor = Colors.redAccent;          
  } else if (score >= 5.0) {
    barColor = Colors.orangeAccent;       
  }

  // 2. SAFE HEIGHT CALCULATION: 
  // If the score is massive (like 180°), we clamp it to a max threshold (e.g., 20°) 
  // so it scales nicely and never overflows the 120px tall graph container container.
  double clampedScore = score.clamp(0.0, 20.0);
  
  // Map the 0-20 scale smoothly to a maximum visual height of 75 pixels
  double visualHeight = (clampedScore / 20.0) * 75.0;

  return Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      // Display the real angle text above the bar (even if it's 180°)
      Text(
        score > 90 ? "Error" : "${score.toStringAsFixed(1)}°", 
        style: const TextStyle(color: Colors.white, fontSize: 10)
      ),
      const SizedBox(height: 4),
      Container(
        width: 28,
        height: visualHeight, // Uses our safe, clamped calculation
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ],
  );
}
}