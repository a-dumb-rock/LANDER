# LANDR Accuracy Plan — getting to "as accurate as possible"

Honest framing: a **single** phone camera cannot reach lab accuracy for knee angles,
because depth (the front–back direction) is poorly estimated from one view. The plan
below climbs from "rough screen" to "research-grade" in tiers. **Nothing here
requires training a model** — every component is pre-trained or rule-based.

## Tier 0 — baseline (what you ran)
Single front camera, MediaPipe **lite**, no refinement.
- Valgus: usable as a *relative* signal (~15–20° absolute error in the literature).
- Knee flexion: under-read from the front (depth problem).

## Tier 1 — implemented now (test in Colab today)
All built into the code in this release:

1. **Stronger pose model.** Switched default from `lite` to `full` (and you can
   request `heavy`). Better keypoints, same workflow. `--model-size full|heavy`.
2. **Refinement pass** wired into `analyze` (on by default): temporal smoothing +
   anatomical limb-length constraint. Removes per-frame jitter that corrupts angles.
   Turn off with `--no-refine`.
3. **Two-view fusion** — the biggest single-camera win. Film a **front** clip *and* a
   **side** clip; LANDR takes **valgus from the front** and **knee/trunk flexion from
   the side**, fixing the depth problem. `python -m landr.cli analyze2 front.mp4 side.mp4`.
4. **Within-athlete fatigue comparison** (already present) — comparing the same
   athlete fresh vs. fatigued cancels most systematic error, so it's trustworthy even
   when absolute degrees aren't.

Expected effect: noticeably more stable valgus, and *real* knee-flexion numbers once
you add the side view.

## Tier 2 — recommended upgrade: Sports2D backbone
[Sports2D](https://github.com/davidpagnon/Sports2D) is a published, open-source tool
that computes joint angles from a single video using **RTMPose** (stronger than
MediaPipe) and converts pixels to meters. It's sport-tuned and `pip install sports2d`.
Swapping it in as the pose backbone is the next accuracy step for single-camera use.
(Scaffold provided in `landr/backends/sports2d_adapter.py` — experimental.)

## Tier 3 — the accurate endgame: Pose2Sim (multi-camera)
[Pose2Sim](https://github.com/perfanalytics/pose2sim) triangulates **2–4 synced
cameras** into a 3D OpenSim model and reports **mean errors of ~0.4–1.6°** — i.e.
research-grade, the real answer to "as accurate as possible." Requires camera
calibration and OpenSim, so it's a bigger setup. [OpenCap](https://www.opencap.ai/)
is a hosted two-phone alternative built on the same idea.

## Validation (how you *prove* accuracy)
Run the pipeline on a public dataset that has marker-based ground truth (e.g. the
synchronised video+mocap+force-plate set, or AthletePose3D) and report valgus/flexion
RMSE with `accuracy.angle_rmse`. This is what turns a claim into a result.

## What this means for your competition story
- **Novelty:** within-athlete *fatigue-vulnerability* + a measured *accuracy gain*.
- **Accuracy you can defend today:** Tier 1 (two-view + refine + full model) for
  relative/fatigue measurements, with Tier 3 named as the path to absolute accuracy.
- Don't over-claim single-camera absolute degrees — claim *relative* and *fatigue*
  accuracy, and validate against public mocap data.
