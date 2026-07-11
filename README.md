# LANDR — ACL-Risk Landing Analysis

LANDR is a two-product biomechanics platform for ACL injury screening and return-to-sport assessment. Both products share the same clinical engine and speak the same language in their reports.

---

## Products

### LANDR Mobile
Single-phone longitudinal monitor. Two views (frontal + sagittal), 2D pose estimation, best for tracking per-athlete trends over time.

- **Accuracy:** ~±9° valgus (improves when athlete is square to the lens)
- **Use case:** Weekly/monthly screening, trend detection, flagging athletes for deeper assessment
- **Platform:** Android (Flutter), talks to `server.py` on the local network

### LANDR Studio
Multi-camera, lab-grade 3D reconstruction for acute screening and return-to-sport clearance.

- **Accuracy:** ~1° valgus (geometry-proven, see below)
- **Use case:** Pre-season screen, post-injury clearance, multi-person team sessions, live rep-by-rep feedback
- **Platform:** Fixed camera rig (2–8 cameras), FastAPI server + web dashboard on `:8010`

---

## How to run

### Mobile backend
```bash
pip install -r requirements.txt
python server.py          # http://localhost:8000
```

### Studio
```bash
python -m studio.server   # dashboard + API  →  http://localhost:8010
python -m studio.selftest # geometry validation
python -m studio.demo     # terminal demo analysis
pytest                    # 36 tests
```

### Mobile app
```bash
cd mobileapp
flutter run
```

---

## Standard test protocol (Drop Vertical Jump)

Both products analyse the same movement:

1. Stand on a **30 cm box** with both feet
2. **Step off** with one foot (like stepping off a curb — do not jump)
3. Bring the other foot off immediately so you're briefly airborne
4. **Land with both feet simultaneously**
5. Immediately jump straight up as high as possible
6. **Land again** — this second landing is what gets measured

**Camera position (Mobile):** 3–4 m from athlete, hip height, athlete facing square to the lens. Record 3–5 trials front, then rotate 90° for side view.

> The in-app pre-test guide (3 pages: setup → movement → camera) walks through this before each recording session. Users can skip it once they know the protocol.

---

## Architecture

```
landr/                    Shared clinical engine (Python)
  biomechanics/           Landing event detection, metric computation
  scoring.py              LESS scoring, risk assessment
  types.py                PoseSequence, AnalysisResult, LessResult, …

server.py                 LANDR Mobile API (port 8000)

studio/                   LANDR Studio — multi-camera 3D product
  calibration.py          Pinhole Camera, CameraRig, DLT resectioning
  triangulation.py        Weighted DLT + RANSAC over views
  anatomical.py           World → anatomical frame rotation
  detector.py             RTMPose per-view 2D (+ DirectML for AMD GPU)
  multiperson.py          Epipolar person association across views
  synthetic.py            Parametric 3D landing generator (ground truth)
  pipeline.py             analyze_capture — end-to-end 3D pipeline
  live.py                 Live streaming, per-camera threads, landing FSM,
                          WebSocket push → dashboard updates per rep
  ingest.py               CLI: videos or .npy keypoint files → analysis
  report.py               Printable HTML/PDF clinical report
  demo.py                 Ready-made synthetic captures
  selftest.py             Geometry validation with known ground truth
  server.py               FastAPI :8010 + WebSocket /ws/live
  web/index.html          Clinician dashboard (3D viewer, risk gauge, LESS,
                          live mode, print report)

mobileapp/lib/
  main.dart               App + navigation + camera screen
  pre_test_screen.dart    3-page DVJ setup guide shown before recording
  session_detail_screen.dart  Per-session results, metrics, LESS breakdown
  session_manager.dart    Athlete roster, session history
  theme.dart              Design tokens (LColors, shadows, typography)

validation/               Real-data accuracy benchmarking vs OpenCap mocap
tests/                    pytest suite (36 tests)
```

---

## Studio accuracy

Run `python -m studio.selftest` to reproduce:

| Check | Result |
|---|---|
| 3D reconstruction, clean keypoints | **0.00 mm** (exact) |
| 3D reconstruction, 1 px detector noise | ~2.4 mm |
| Knee flexion recovery | ~0.1° |
| Knee valgus @ initial contact | < 1° |
| Athlete yawed 45° — single camera vs Studio | single: 30–45° error · Studio: ~0.6° |
| Multi-person association | correct |

**Proven:** geometry is correct end-to-end.  
**Pending:** real-world validation vs marker mocap (needs live synchronised capture or OpenCap LabValidation set).

---

## Clinical metrics

All results are reported per the **Landing Error Scoring System (LESS)**:

| Metric | Threshold |
|---|---|
| Knee flexion @ initial contact | ≥ 30° |
| Knee flexion @ lowest point | ≥ 70° |
| Peak knee valgus | < 10° |
| Bilateral asymmetry | < 15% |
| Trunk lean | < 30° |

---

## Live capture (Studio)

Connect webcams or RTSP streams; the server detects rep completion via a hip-height FSM and pushes results to the dashboard ~0.5 s after each landing via WebSocket.

```bash
# AMD RX 6600 / Intel Arc on Windows — DirectML backend
pip install onnxruntime-directml
# Set device = "dml" in the Live tab of the dashboard
```

```bash
# CLI from video files (runs RTMPose detection)
python -m studio.ingest --videos front.mp4 side.mp4 left.mp4 right.mp4 \
                         --rig rig.json --athlete "Alex Rivera"

# CLI from pre-saved keypoints (no GPU needed on analysis machine)
python -m studio.ingest --keypoints cam0.npy cam1.npy --rig rig.json

# Print HTML clinical report to file
python -m studio.ingest --keypoints *.npy --rig rig.json --report-html > report.html
```

---

## Repo layout

```
LANDR/
├── landr/              shared clinical engine
├── studio/             Studio product (3D, live, reports)
├── mobileapp/          Flutter Android app
├── server.py           Mobile backend (port 8000)
├── validation/         accuracy benchmarking vs OpenCap
├── tests/              pytest suite
└── README.md
```
