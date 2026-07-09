# Real-data accuracy validation

Replaces LANDR's *synthetic* accuracy claim ("we reduce the ~18–20° single-camera
error") with a number measured on **real** landings that have motion-capture ground
truth — the [OpenCap Lab Validation dataset](https://simtk.org/projects/opencap)
(10 subjects, drop vertical jump, synchronized 5-camera video + marker mocap,
Apache 2.0).

## What is validated, and against what

| Metric | Prediction | Ground truth | Camera |
|---|---|---|---|
| **Knee flexion** | LANDR angle from RTMPose keypoints | OpenSim IK `knee_angle_r/l` (`.mot`) — field gold standard | ~side (sagittal) |
| **Knee valgus (FPPA)** | LANDR `signed_knee_valgus` from keypoints | Same geometry on mocap hip/knee/ankle markers (`.trc`) | ~front (frontal) |

RTMPose is 2D (image plane), so each metric is validated from the camera whose
plane it lives in. Valgus has no standard OpenSim frontal-plane knee DOF, so its
ground truth is a marker-derived projection computed with **LANDR's own geometry** —
this is why the literature reports valgus as the harder metric (r ≈ 0.45).

## Anti-overfitting protocol (why the number is trustworthy)

1. **Split by subject** into a small *tune* set and a held-out *test* set. No
   subject appears in both.
2. On the tune set only, fit **one** global convention per metric (a single sign +
   single offset) that reconciles LANDR's angle definition with the ground truth.
3. **Freeze** it, then evaluate once on the test set. Report naive vs improved
   RMSE there.

Explicitly disallowed (would fake the result): per-frame time warping (DTW),
per-clip offsets, and any parameter fit on the test split. Alignment allows only a
single global time lag per clip (video and mocap clocks start at different instants).

## Layout

```
validation/
├── opensim_io.py     # .mot / .trc readers (stable formats)
├── ground_truth.py   # GT angles, reusing landr geometry (apples-to-apples)
├── runner.py         # video -> LANDR naive/improved angle series (RTMPose)
├── align.py          # resample + single global lag + global convention + RMSE
├── benchmark_real.py # subject split, fit-on-tune, score-on-test, aggregate
├── adapter.py        # OpenCap folder/marker/axis mapping  ← finalise after download
├── discover_cli.py   # prints the real layout to finalise adapter.py
└── selftest.py       # synthetic end-to-end proof (no data/backend needed)
```

## Status / next steps

- [x] Harness built and self-tested on synthetic data (`python -m validation.selftest`).
- [ ] Download + unzip `LabValidation_withVideos.zip` (see README of this dir / chat).
- [ ] `python -m validation.discover_cli <root>` → finalise `adapter.py` names + axis map.
- [ ] Wire `resolve_trials()` (subject → drop-jump trials → side/front video + `.mot`/`.trc`).
- [ ] Run the benchmark; record naive vs improved RMSE per metric on the held-out set.
