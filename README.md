# LANDR  (v2 — fatigue-aware)

**Landing Analysis for Non-contact-injury Detection & Risk**

Fatigue-aware ACL injury-risk screening you can trust from a single phone camera.

> *Injuries happen when athletes are fatigued, but screening is done when they're
> fresh.* LANDR measures the risk that actually matters — how an athlete's landing
> mechanics degrade under fatigue — and closes the accuracy gap that has kept
> single-camera screening from being trusted.

This version is built around two focused, defensible contributions (after a
prior-art review showed basic automated landing screening is already well-explored):

- **Pillar 1 — Accuracy.** Naive single-camera knee-valgus error is ~18–20°. A
  temporal-smoothing + anatomical-constraint pipeline reduces it, with a benchmark
  that *quantifies the gain*. (`landr/accuracy.py`)
- **Pillar 2 — Fatigue.** Compare an athlete fresh vs. fatigued and compute a
  personal *fatigue-vulnerability* signature — how much their mechanics decay when
  tired. (`landr/fatigue.py`)

> ⚠️ **Decision-support, not diagnosis.** A screening aid for coaches and
> clinicians, not a medical device. Always keep a human in the loop.

---

## Runs out of the box — no video, no API keys

```bash
pip install numpy scipy matplotlib

python -m landr.cli demo --quality poor     # basic screen (synthetic landing)
python -m landr.cli fatigue --plot f.png    # Pillar 2: fresh vs fatigued + plot
python -m landr.cli benchmark               # Pillar 1: accuracy error reduction
```

Or just double-click **`setup_and_run.command`** (macOS/Linux) — it installs
everything and runs all three.

Analyze a real video (needs `mediapipe`):

```bash
pip install mediapipe opencv-python
python -m landr.cli analyze path/to/jump.mp4 --plot result.png --out result.json
```

### Maximum-accuracy recipe

The most accurate configuration the codebase supports, from a phone:

```bash
# 1) film TWO clips of the same jump: one FRONT, one SIDE
# 2) install the RTMPose backend (state-of-the-art 2D keypoints, used by Sports2D)
pip install rtmlib onnxruntime
# 3) fuse them, RTMPose backend, max model, refinement on (default)
python -m landr.cli analyze2 front.mp4 side.mp4 --backend rtmpose --accuracy max --plot out.png
```

Why this is the ceiling for camera-only: two views fix the depth problem (valgus
from the front, knee/trunk flexion from the side), RTMPose gives the best 2D
keypoints, and the refinement pass removes jitter. True lab-grade accuracy (~1°)
requires multi-camera **Pose2Sim** — a hardware/calibration setup, not a code
change (see `ACCURACY_PLAN.md`). If `rtmpose` isn't installed, LANDR automatically
falls back to MediaPipe.

Use a real vision-language model for the written report (optional):

```bash
cp .env.example .env        # add OPENAI_API_KEY or GOOGLE_API_KEY
python -m landr.cli demo --provider openai
```

## What the two new commands show

**`fatigue`** simulates a fresh and a fatigued landing for the same athlete,
computes the change in valgus / knee-flexion / asymmetry / LESS, and prints a
0–100 fatigue-vulnerability score with a plain-language report. With real data,
pass two saved analyses: `--fresh fresh.json --fatigued fatigued.json`.

**`benchmark`** takes a clean synthetic landing as ground truth, adds realistic
pose noise, and reports knee-valgus/flexion RMSE for the naive vs improved
pipeline — demonstrating the accuracy gain. (Real validation needs marker-based
motion capture; `accuracy.angle_rmse` accepts real data too.)

## Project layout

```
landr/
├── landr/
│   ├── accuracy.py          # ★ Pillar 1: temporal + limb-length correction + benchmark
│   ├── fatigue.py           # ★ Pillar 2: fresh-vs-fatigued vulnerability score
│   ├── synthetic.py         # synthetic jumps with `fatigue` and `noise` knobs
│   ├── config.py, types.py
│   ├── pose/estimator.py    # MediaPipe wrapper (graceful fallback)
│   ├── biomechanics/        # geometry, metrics, landing detection
│   ├── scoring/             # automated LESS + risk
│   ├── reasoning/           # pluggable VLM report (mock/openai/gemini)
│   ├── pipeline.py, viz.py, cli.py
├── examples/run_demo.py
├── tests/                   # pytest (incl. test_fatigue.py, test_accuracy.py)
├── docs/ARCHITECTURE.md
└── setup_and_run.command
```

## Roadmap (Phases 0–2 = competition scope)

- **0 — Baseline:** reproduce naive valgus error on public data (the number you beat).
- **1 — Accuracy:** temporal + anatomical correction; benchmark the RMSE gain.
- **2 — Fatigue:** detect fresh→fatigued shift on the public fatigue dataset; define
  the vulnerability score.
- **3 — Field pilot:** self-collected fresh/fatigued phone clips.
- **4 — Season + learned model:** longitudinal tracking, outcome-validated risk model.

## Honesty notes

- Single-camera depth is noisy; two-view capture and per-athlete calibration help.
- The automated LESS is an *approximation* with contested predictive validity —
  treated as a baseline to improve upon, not ground truth.
- The benchmark is a simulation of jitter reduction; real accuracy claims require
  marker-based motion capture.

See `docs/ARCHITECTURE.md` for data contracts and the validation plan.

## License

MIT (placeholder).
