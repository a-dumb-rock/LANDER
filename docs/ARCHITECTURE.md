# LANDR Architecture (v2)

Four-stage pipeline plus two v2 capability modules.

```
video ─▶ pose/ ─▶ biomechanics/ ─▶ scoring/ ─▶ reasoning/ ─▶ AnalysisResult
         PoseSeq   metrics+events   LESS+risk   report text

         ▲ accuracy.py  (Pillar 1: correct the PoseSequence before metrics)
         fatigue.py     (Pillar 2: compare two AnalysisResults: fresh vs fatigued)
```

## Data contracts (`landr/types.py`)

- **PoseSequence** — `landmarks (T,J,3)`, `fps`, `visibility (T,J)`, `meta`.
- **LandingEvents** — `initial_contact`, `lowest_point`, `stabilized`.
- **LessResult / RiskResult / AnalysisResult** — scoring + full output.
- **FatigueComparison** (`fatigue.py`) — deltas, vulnerability_score, category.

## Core stages

1. **pose/** — MediaPipe wrapper → PoseSequence (optional dep; swap for RTMPose/OpenCap).
2. **biomechanics/** — pure geometry, landing-event detection, angle metrics.
3. **scoring/** — transparent automated LESS + rule-based risk.
4. **reasoning/** — pluggable VLM report (mock/openai/gemini), graceful fallback.

## Pillar 1 — accuracy.py

- `temporal_smooth(landmarks)` — Savitzky-Golay over time (falls back to moving
  average without scipy). Removes per-frame jitter, the dominant monocular error.
- `enforce_limb_lengths(landmarks)` — fix thigh/shank to median length per clip
  (a cheap anatomical constraint, BioPose-style intuition).
- `improve(landmarks)` — both, in order.
- `angle_rmse`, `run_accuracy_benchmark(noise_std)` — quantify valgus/flexion error
  reduction vs a clean ground-truth sequence. `angle_rmse` also accepts real mocap.
- `improved_sequence(seq)` — return a corrected PoseSequence to feed the pipeline.

To use in the real pipeline: call `improved_sequence()` on the estimator output
before `analyze_sequence()`.

## Pillar 2 — fatigue.py

- `compare(fresh, fatigued)` → `FatigueComparison`: change in peak valgus, knee
  flexion at contact, energy absorption, asymmetry, and LESS; a 0–100
  fatigue-vulnerability score; and a category (robust/moderate/vulnerable).
- `fatigue_report(cmp, name)` — plain-language report.
- Key idea: **within-athlete change** cancels per-person bias, so it's robust and
  it relaxes the accuracy requirement — Pillars 1 & 2 reinforce each other.

## Synthetic data (`synthetic.py`)

`synthetic_jump(quality, fatigue, noise, ...)`:
- `fatigue ∈ [0,1]` pushes mechanics toward the injury pattern (for Pillar 2).
- `noise` is landmark jitter; `noise=0` gives clean ground truth (for Pillar 1).

## Validation plan

| Claim | Ground truth | Metric | Target |
|---|---|---|---|
| P1 accuracy gain | Marker mocap / force plate | Valgus & flexion RMSE | ~18–20° → <10° |
| P2 fatigue detection | Fresh vs fatigued labels | Δ valgus/flexion; classifier AUC | reliably detect shift |
| P2 signature stability | Repeat sessions/athlete | Test–retest of the curve | stable within athlete |
| Whole system | Human-LESS baseline | Added value over a fresh static screen | beat the baseline |

Public datasets to plug in: Nature Sci. Data 2025 fatigued/non-fatigued
jump-landings; AthletePose3D; synchronised video+mocap+force-plate sets.

## Next implementation steps

1. Wire `improved_sequence()` into `analyze()` as an opt-in flag.
2. Add a two-view (front+side) capture path for the depth-sensitive valgus axis.
3. Build a validation harness over a public mocap dataset (emit the table above).
4. Replace rule-based risk + vulnerability weights with a learned, calibrated,
   outcome-validated model (Phase 4).
