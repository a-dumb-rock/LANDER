"""Walk the OpenCap folder tree and build TrialAngles for every DJ trial.

For each subject x trial:
  - front video  (Cam2 / DJ1_syncdWithMocap.avi)  -> LANDR valgus series
  - side video   (Cam0 / DJ1_syncdWithMocap.avi)  -> LANDR flexion series
  - IK .mot      (OpenSimData/Mocap/IK/DJ1.mot)   -> GT flexion (knee_angle_r/l)
                                                      GT valgus  (hip_adduction_r/l, negated)
"""

from __future__ import annotations

import os

from .adapter import DataLayout
from .benchmark_real import TrialAngles
from .ground_truth import flexion_from_mot, valgus_from_ik
from .opensim_io import read_mot
from .runner import angles_from_video


def _synced_video(root: str, subject: str, cam: str, trial: str) -> str | None:
    base = os.path.join(root, subject, "VideoData", "Session0", cam, trial)
    synced = os.path.join(base, f"{trial}_syncdWithMocap.avi")
    raw    = os.path.join(base, f"{trial}.avi")
    if os.path.exists(synced):
        return synced
    if os.path.exists(raw):
        return raw
    return None


def _ik_path(root: str, subject: str, trial: str) -> str:
    return os.path.join(root, subject, "OpenSimData", "Mocap", "IK", f"{trial}.mot")


def _trc_path(root: str, subject: str, trial: str) -> str:
    return os.path.join(root, subject, "MarkerData", "Mocap", f"{trial}.trc")


def _dj_trials(root: str, subject: str, layout: DataLayout) -> list[str]:
    """Return drop-jump trial names (e.g. ['DJ1','DJ2','DJ3']) for a subject."""
    ik_dir = os.path.join(root, subject, "OpenSimData", "Mocap", "IK")
    if not os.path.isdir(ik_dir):
        return []
    trials = []
    for f in sorted(os.listdir(ik_dir)):
        if not f.endswith(".mot"):
            continue
        name = f[:-4]
        if any(k in name for k in layout.dropjump_keys) and "Asym" not in name:
            trials.append(name)
    return trials


def resolve_all_trials(
    root: str,
    layout: DataLayout,
    backend: str = "rtmpose",
    verbose: bool = True,
    cache_dir: str | None = None,
) -> list[TrialAngles]:
    """Run pose estimation on every DJ trial and return TrialAngles list."""
    subjects = sorted(
        d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))
    )
    all_trials: list[TrialAngles] = []

    for subject in subjects:
        trials = _dj_trials(root, subject, layout)
        if not trials:
            if verbose:
                print(f"  [{subject}] no DJ trials found, skipping")
            continue

        for trial in trials:
            if verbose:
                print(f"  [{subject}/{trial}] processing...", flush=True)

            front_vid = _synced_video(root, subject, layout.front_camera, trial)
            side_vid  = _synced_video(root, subject, layout.side_camera,  trial)
            ik_file   = _ik_path(root, subject, trial)

            missing = [n for n, p in [
                ("front_video", front_vid),
                ("side_video",  side_vid),
                ("IK_mot", ik_file if os.path.exists(ik_file) else None),
            ] if not p]
            if missing:
                if verbose:
                    print(f"    skip -- missing: {missing}")
                continue

            try:
                # --- pose estimation (slow; cached after first run) ---
                front_ang = angles_from_video(front_vid, backend=backend, cache_dir=cache_dir)
                side_ang  = angles_from_video(side_vid,  backend=backend, cache_dir=cache_dir)

                # --- ground truth from IK (same time window for both metrics) ---
                mot = read_mot(ik_file)
                t_ik_r, gt_flex_r = flexion_from_mot(mot, "right")
                t_ik_l, gt_flex_l = flexion_from_mot(mot, "left")
                t_vg_r, gt_valg_r = valgus_from_ik(mot, "right")
                t_vg_l, gt_valg_l = valgus_from_ik(mot, "left")

                fps = side_ang.fps

                for side, t_ik, gt_flex, t_vg, gt_valg, ang_f, ang_s in [
                    ("right", t_ik_r, gt_flex_r, t_vg_r, gt_valg_r, front_ang, side_ang),
                    ("left",  t_ik_l, gt_flex_l, t_vg_l, gt_valg_l, front_ang, side_ang),
                ]:
                    all_trials.append(TrialAngles(
                        subject=subject, trial=trial, metric="flexion", side=side, fps=fps,
                        t_pred=ang_s.time, y_naive=ang_s.naive["flexion"][side],
                        y_improved=ang_s.improved["flexion"][side],
                        t_gt=t_ik, y_gt=gt_flex,
                    ))
                    all_trials.append(TrialAngles(
                        subject=subject, trial=trial, metric="valgus", side=side, fps=fps,
                        t_pred=ang_f.time, y_naive=ang_f.naive["valgus"][side],
                        y_improved=ang_f.improved["valgus"][side],
                        t_gt=t_vg, y_gt=gt_valg,
                    ))

                if verbose:
                    print(f"    ok ({len(all_trials)} total trial-sides so far)")

            except Exception as exc:
                import traceback
                if verbose:
                    print(f"    ERROR: {exc}")
                    traceback.print_exc()
                continue

    return all_trials
