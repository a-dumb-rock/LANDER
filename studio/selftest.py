"""Rigorous synthetic validation of the LANDR Studio geometry.

This proves the *pipeline* is correct end-to-end, using ground truth we fully
control. It does NOT claim real-world accuracy (that needs real multi-camera
capture) — it proves that IF the 2D detections are good, Studio recovers the right
3D and the right clinical angles.

Four checks:
  1. 3D reconstruction error (mm) vs the known world skeleton.
  2. Clinical-angle recovery (flexion, valgus) vs ground truth, clean and noisy.
  3. Orientation invariance: as the athlete yaws off-axis, a single camera's 2D
     valgus degrades badly while Studio's 3D stays accurate — the core reason the
     motion-camera product exists.
  4. Multi-person association across views (epipolar matching) puts the right
     detections together.

Run:  python -m studio.selftest
"""

from __future__ import annotations

import numpy as np

from landr import config
from landr.biomechanics import compute_metrics, detect_landing_events
from landr.types import PoseSequence

from .anatomical import to_anatomical
from .calibration import make_arc_rig
from .multiperson import associate_two_views
from .synthetic import make_landing_capture, project_to_views
from .triangulation import triangulate_sequence

_USED = [
    config.NOSE, config.LEFT_SHOULDER, config.RIGHT_SHOULDER, config.LEFT_HIP,
    config.RIGHT_HIP, config.LEFT_KNEE, config.RIGHT_KNEE, config.LEFT_ANKLE,
    config.RIGHT_ANKLE, config.LEFT_FOOT_INDEX, config.RIGHT_FOOT_INDEX,
]


def _engine(seq: PoseSequence, events=None) -> dict:
    if events is None:
        events = detect_landing_events(seq)
    return compute_metrics(seq, events)


def _angle_summary(metrics: dict) -> dict:
    return {
        "flexion_ic": metrics["at_initial_contact"]["knee_flexion_deg"],
        "flexion_low": metrics["at_lowest_point"]["knee_flexion_deg"],
        "valgus_ic": metrics["at_initial_contact"]["knee_valgus_deg"],
        "valgus_low": metrics["at_lowest_point"]["knee_valgus_deg"],
        "peak_valgus": max(
            abs(metrics["peak_valgus_deg"]["left"]),
            abs(metrics["peak_valgus_deg"]["right"]),
        ),
    }


def _studio_reconstruct(world: PoseSequence, rig, noise: float, seed: int) -> PoseSequence:
    kp, conf = project_to_views(world, rig, pixel_noise=noise, seed=seed)
    pts3d, conf3d = triangulate_sequence(rig.cameras, kp, conf, robust=noise > 0)
    recon = PoseSequence(landmarks=pts3d, fps=world.fps, visibility=conf3d,
                         meta={"frame": "world"})
    return recon


def _single_camera_metrics(world: PoseSequence, cam) -> dict:
    """Emulate the LANDR-Mobile 2D pipeline from ONE camera (image plane = x,-y)."""
    proj = cam.project(world.landmarks.reshape(-1, 3)).reshape(
        world.n_frames, config.NUM_LANDMARKS, 2
    )
    pts = np.zeros((world.n_frames, config.NUM_LANDMARKS, 3))
    pts[:, :, 0] = proj[:, :, 0]
    pts[:, :, 1] = -proj[:, :, 1]  # flip image-y so up is +y (mobile convention)
    seq = PoseSequence(landmarks=pts, fps=world.fps, visibility=world.visibility,
                       meta={"frame": "image"})
    return _engine(seq)


def recon_error_mm(world: PoseSequence, rig, noise: float, seed: int) -> float:
    recon = _studio_reconstruct(world, rig, noise, seed)
    gt = world.landmarks[:, _USED, :]
    est = recon.landmarks[:, _USED, :]
    d = np.linalg.norm(est - gt, axis=-1)  # metres per joint per frame
    return float(np.sqrt(np.nanmean(d**2)) * 1000.0)


_GAIN = 3.0  # injected medial-collapse (cm) -> physiological valgus


def run() -> dict:
    rig = make_arc_rig(n_cameras=4, radius=3.0, height=1.2, arc_deg=160.0)
    world = make_landing_capture(n_frames=90, fps=60.0, valgus_gain=_GAIN,
                                 asymmetry=0.12, facing_deg=0.0, seed=1)

    # Ground-truth angles AND the ground-truth landing events. We reuse these exact
    # event frames for the measured pass so we isolate GEOMETRY error from the
    # (separate) sensitivity of frame-based event detection to detector noise.
    gt_seq = to_anatomical(world, rig.up)
    gt_events = detect_landing_events(gt_seq)
    gt = _angle_summary(_engine(gt_seq, gt_events))

    results = {"ground_truth": gt, "rig_cameras": len(rig), "checks": {}}

    for label, noise in [("clean", 0.0), ("noise_1px", 1.0), ("noise_2px", 2.0)]:
        recon = _studio_reconstruct(world, rig, noise, seed=7)
        rseq = to_anatomical(recon, rig.up)
        meas = _angle_summary(_engine(rseq, gt_events))  # same frames as GT
        # Informational: how much the auto event detector drifts under this noise.
        ev_drift = abs(detect_landing_events(rseq).initial_contact - gt_events.initial_contact)
        results["checks"][label] = {
            "recon_mm": round(recon_error_mm(world, rig, noise, seed=7), 3),
            "flexion_ic_err": round(abs(meas["flexion_ic"] - gt["flexion_ic"]), 3),
            "flexion_low_err": round(abs(meas["flexion_low"] - gt["flexion_low"]), 3),
            "valgus_ic_err": round(abs(meas["valgus_ic"] - gt["valgus_ic"]), 3),
            "valgus_peak_err": round(abs(meas["peak_valgus"] - gt["peak_valgus"]), 3),
            "event_ic_drift_frames": int(ev_drift),
            "measured": {k: round(v, 2) for k, v in meas.items()},
        }

    # --- Check 3: orientation invariance (the motion-camera thesis) -------------
    orient = []
    for yaw in [0, 15, 30, 45]:
        w = make_landing_capture(n_frames=90, fps=60.0, valgus_gain=_GAIN,
                                 asymmetry=0.12, facing_deg=yaw, seed=1)
        w_seq = to_anatomical(w, rig.up)
        ev = detect_landing_events(w_seq)
        gt_y = _angle_summary(_engine(w_seq, ev))
        recon = _studio_reconstruct(w, rig, noise=1.0, seed=7)
        studio_y = _angle_summary(_engine(to_anatomical(recon, rig.up), ev))
        # Single front-ish camera (middle of the arc), its own event detection.
        single_y = _angle_summary(_single_camera_metrics(w, rig.cameras[len(rig) // 2]))
        orient.append({
            "yaw_deg": yaw,
            "true_peak_valgus": round(gt_y["peak_valgus"], 2),
            "studio_peak_valgus": round(studio_y["peak_valgus"], 2),
            "studio_err": round(abs(studio_y["peak_valgus"] - gt_y["peak_valgus"]), 2),
            "single_cam_peak_valgus": round(single_y["peak_valgus"], 2),
            "single_cam_err": round(abs(single_y["peak_valgus"] - gt_y["peak_valgus"]), 2),
        })
    results["orientation"] = orient

    # --- Check 4: multi-person association --------------------------------------
    p1 = make_landing_capture(n_frames=1, valgus_gain=6.0, facing_deg=0, seed=2)
    p2 = make_landing_capture(n_frames=1, valgus_gain=18.0, facing_deg=20, seed=3)
    # shift person 2 sideways so they occupy different world space
    p2.landmarks[..., 0] += 0.8
    ca, cb = rig.cameras[0], rig.cameras[3]
    people_a = np.stack([ca.project(p1.landmarks[0]), ca.project(p2.landmarks[0])])
    people_b = np.stack([cb.project(p1.landmarks[0]), cb.project(p2.landmarks[0])])
    conf = np.ones((2, config.NUM_LANDMARKS))
    matches = associate_two_views(ca, cb, people_a, people_b, conf, conf)
    correct = sorted(matches) == [(0, 0), (1, 1)]
    results["multiperson"] = {"matches": matches, "correct": correct}

    return results


def _fmt(results: dict) -> str:
    L = []
    L.append("=" * 66)
    L.append("  LANDR STUDIO — geometry self-test (synthetic ground truth)")
    L.append("=" * 66)
    gt = results["ground_truth"]
    L.append(f"  Rig: {results['rig_cameras']} calibrated cameras")
    L.append(f"  Ground-truth landing:  flexion@IC {gt['flexion_ic']:.1f}°  "
             f"flexion@low {gt['flexion_low']:.1f}°  peak valgus {gt['peak_valgus']:.1f}°")
    L.append("-" * 66)
    L.append("  1-2) Reconstruction + angle recovery (angles sampled at fixed GT frames)")
    for label, c in results["checks"].items():
        L.append(f"    {label:9s}  3D err {c['recon_mm']:6.2f} mm   "
                 f"flexion@IC err {c['flexion_ic_err']:.2f}°   "
                 f"valgus@IC err {c['valgus_ic_err']:.2f}°   "
                 f"peak(FPPA) err {c['valgus_peak_err']:.2f}°")
    L.append("-" * 66)
    L.append("  3) Orientation invariance — Studio 3D vs a single 2D camera")
    L.append(f"    {'yaw':>4} {'true':>7} {'studio':>8} {'err':>6} | {'1-cam':>7} {'err':>6}")
    for o in results["orientation"]:
        L.append(f"    {o['yaw_deg']:>3}° {o['true_peak_valgus']:>7.1f} "
                 f"{o['studio_peak_valgus']:>8.1f} {o['studio_err']:>6.2f} | "
                 f"{o['single_cam_peak_valgus']:>7.1f} {o['single_cam_err']:>6.2f}")
    L.append("-" * 66)
    mp = results["multiperson"]
    L.append(f"  4) Multi-person association: {mp['matches']}  "
             f"-> {'CORRECT' if mp['correct'] else 'WRONG'}")
    L.append("=" * 66)
    return "\n".join(L)


def main() -> int:
    results = run()
    print(_fmt(results))

    clean = results["checks"]["clean"]
    noisy = results["checks"]["noise_1px"]
    checks = {
        "clean reconstruction exact (< 0.01 mm)": clean["recon_mm"] < 0.01,
        "clean angles exact (< 0.05°)": clean["flexion_ic_err"] < 0.05
        and clean["valgus_ic_err"] < 0.05
        and clean["valgus_peak_err"] < 0.05,
        "1px reconstruction < 6 mm": noisy["recon_mm"] < 6.0,
        "1px flexion@IC recovery < 1.5°": noisy["flexion_ic_err"] < 1.5,
        "1px valgus@IC recovery < 1.0°": noisy["valgus_ic_err"] < 1.0,
        "multi-person association correct": results["multiperson"]["correct"],
        "3D beats single camera off-axis": all(
            o["studio_err"] < o["single_cam_err"] for o in results["orientation"][1:]
        ),
    }
    ok = all(checks.values())
    print()
    for name, passed in checks.items():
        print(f"    [{'PASS' if passed else 'FAIL'}] {name}")
    print(f"\n  {'PASS — Studio geometry validated' if ok else 'FAIL — see above'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
