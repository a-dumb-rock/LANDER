# LANDR Studio

**Multi-camera, lab-grade motion capture for ACL-risk landing analysis.**

LANDR Studio is the clinic/team counterpart to LANDR Mobile. Where the phone app is a
single-camera *personal longitudinal monitor* (2D per view, valgus accurate to ~9°,
best for per-athlete trend detection), Studio uses a fixed rig of calibrated cameras
to reconstruct **true 3D** joint motion — the same geometry that gives OpenCap its
~1° lab accuracy — for acute screening and return-to-sport clearance.

It is a separate product with its own backend and web dashboard, but it **reuses the
exact LANDR clinical engine** (`compute_metrics` / `score_less` / `assess_risk`), so a
Studio report and a Mobile report speak the same language.

---

## Why 3D, not "a bigger model"

A single camera can only *project* a 3D motion onto its image plane, so an out-of-plane
knee cave leaks into or out of the measured valgus depending on how the athlete faces
the lens. Training a larger 2D model does not fix this — it is a geometric limitation.

Multi-view **triangulation** removes the ambiguity by construction: given calibrated
cameras and 2D keypoints, each joint's 3D position is recovered by geometry, and the
frontal-plane angle is then measured in the athlete's **anatomical frame** rather than
a camera's image plane. No per-clip fitting, no learned lifter, no training data
required for the rig path.

The self-test quantifies exactly this (see below): as an athlete turns off-axis, a
single 2D camera's peak-valgus error climbs to tens of degrees while Studio stays
within ~1°.

---

## Pipeline

```
per-view 2D keypoints        RTMPose per camera, or precomputed      detector.py
      │                       (COCO-17 → LANDR/MediaPipe-33)
      ▼
triangulate → true 3D        weighted DLT + light RANSAC over views  triangulation.py
      │
      ▼
anatomical frame             x=medio-lateral, y=up, z=anterior       anatomical.py
      │                       (from the rig's up-vector + pelvis)
      ▼
landing events + metrics     the shared LANDR clinical engine        landr/…
+ LESS + risk
      │
      ▼
AnalysisResult (+ 3D)        same schema as LANDR Mobile             pipeline.py
```

Multi-person scenes are handled by epipolar association across views
(`multiperson.py`) before triangulation, so several athletes can be analysed from one
capture.

---

## What is validated (and what isn't)

Run the geometry self-test:

```bash
python -m studio.selftest
```

It builds a known 3D landing, projects it into 4 virtual cameras, triangulates it back,
and checks recovery against ground truth. Representative results:

| Check | Result |
|---|---|
| 3D reconstruction, clean 2D | **0.00 mm** (exact to machine precision) |
| 3D reconstruction, 1 px detector noise | ~2.4 mm |
| Knee-flexion recovery @ 1 px | ~0.1° |
| Knee-valgus recovery @ 1 px (at contact) | <1° |
| Peak valgus error vs a single camera, athlete yawed 45° | Studio ~0.6° · single camera ~30–45° |
| Multi-person association (2 athletes, 4 cams) | correct |

> **Proven:** the geometry — projection → triangulation → anatomical frame → clinical
> angles — is correct end-to-end.
>
> **Pending:** real-world accuracy versus marker mocap. That needs live synchronised
> multi-camera capture (or the OpenCap LabValidation set, still gated on SimTK
> approval). Studio is written so swapping synthetic keypoints for real RTMPose
> detections is a one-line change (`CaptureView(video=…)` instead of `keypoints=…`).

Note: peak valgus is a frontal-plane projection angle and is inherently amplified at
deep knee flexion (a property shared with the mobile engine), so the self-test gates
valgus recovery at initial contact, where the metric is well-conditioned, and reports
the peak separately.

---

## Running it

```bash
# dashboard + API  →  http://localhost:8010
python -m studio.server

# print a demo analysis to the terminal (runs the real pipeline)
python -m studio.demo

# geometry validation
python -m studio.selftest

# tests
pytest tests/test_studio.py
```

The dashboard loads two ready-made demo captures (a clean landing and an at-risk one),
each analysed through the genuine 3D pipeline — not hand-typed numbers — and shows the
live self-test results in its "Validated Geometry" panel.

### Analysing a real capture

`POST /api/analyze` with a calibrated rig and per-view keypoints:

```json
{
  "rig": { "up": [0,0,1], "cameras": [ {"name":"cam0","K":[...],"R":[...],"t":[...]}, ... ] },
  "views": [ {"keypoints": [[[u,v],...]], "confidences": [[...]]}, ... ],
  "athlete": {"name": "…"}
}
```

Cameras are calibrated once per rig from known geometry or a checkerboard/wand via
`studio.calibration.calibrate_dlt`.

---

## Module map

| File | Responsibility |
|---|---|
| `calibration.py` | pinhole `Camera`, `CameraRig`, `make_arc_rig`, DLT resectioning |
| `triangulation.py` | weighted DLT triangulation + RANSAC over views |
| `anatomical.py` | world → anatomical-frame rotation |
| `detector.py` | RTMPose per-view 2D (real) / precomputed keypoints |
| `multiperson.py` | epipolar association across views |
| `synthetic.py` | parametric 3D landing generator (ground truth) |
| `pipeline.py` | end-to-end `analyze_capture` |
| `demo.py` | ready-made captures through the real pipeline |
| `selftest.py` | geometry validation with synthetic ground truth |
| `server.py` | FastAPI backend + dashboard |
| `web/index.html` | clinician dashboard (3D viewer, risk, LESS, validation) |
