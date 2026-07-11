"""Rank held-out drop-jump flexion clips by error and diagnose the worst ones.

Flexion always comes from the SIDE camera (Cam0), so a bad clip = a side-view
tracking failure. For each test trial-side we report the flexion RMSE (fixed
convention), then for the worst clips we load the cached pose and report keypoint
visibility/confidence + frame jitter to tell occlusion/tracking-failure apart.
"""

from __future__ import annotations

import hashlib
import os
import pickle

import numpy as np

from landr import config
from .adapter import DataLayout
from .align import align_series, rmse
from .benchmark_real import fit_conventions
from .resolve_trials import _synced_video, resolve_all_trials

ROOT = "C:/Users/sagar/opencap_data/LabValidation_withVideos"
CACHE = "C:/Users/sagar/LANDR/validation/pose_cache"
TUNE = {"subject10", "subject11"}


def _cached_pose(video_path: str):
    key = hashlib.md5(f"{video_path}::rtmpose::landmarks".encode()).hexdigest()
    p = os.path.join(CACHE, f"{key}.pkl")
    if not os.path.exists(p):
        return None
    with open(p, "rb") as f:
        return pickle.load(f)


def _leg_visibility(seq, side: str) -> tuple[float, float]:
    """Mean visibility of hip/knee/ankle for a leg, and fraction of low-vis frames."""
    if seq is None or seq.visibility is None:
        return float("nan"), float("nan")
    idx = list(config.LEG_CHAINS[side])
    vis = np.asarray(seq.visibility)[:, idx]
    return float(vis.mean()), float((vis < 0.5).mean())


def main() -> None:
    layout = DataLayout(root=ROOT)
    trials = resolve_all_trials(ROOT, layout, backend="rtmpose", verbose=False, cache_dir=CACHE)
    conv = fit_conventions([t for t in trials if t.subject in TUNE])["flexion"]

    rows = []
    for t in trials:
        if t.subject in TUNE or t.metric != "flexion":
            continue
        ap = align_series(t.t_pred, t.y_naive, t.t_gt, t.y_gt, convention=conv, ref_fps=60.0)
        rows.append((rmse(ap.pred, ap.gt), t.subject, t.trial, t.side))
    rows.sort(reverse=True)

    vals = np.array([r[0] for r in rows])
    print(f"flexion clips: n={len(rows)}  mean={vals.mean():.1f}  median={np.median(vals):.1f}  "
          f"p90={np.percentile(vals,90):.1f}  max={vals.max():.1f}")
    print(f"clips over 20 deg: {(vals>20).sum()}/{len(rows)}   over 30 deg: {(vals>30).sum()}/{len(rows)}\n")

    print(f"{'RMSE':>6}  {'subject':9} {'trial':6} {'side':5}  {'legVis':>6} {'%lowVis':>7}")
    for r, subj, trial, side in rows[:8]:
        vid = _synced_video(ROOT, subj, layout.side_camera, trial)
        seq = _cached_pose(vid) if vid else None
        mv, lo = _leg_visibility(seq, side)
        print(f"{r:6.1f}  {subj:9} {trial:6} {side:5}  {mv:6.2f} {lo*100:6.0f}%")

    # contrast: mean visibility on the BEST clips
    print("\nbest 5 clips (for contrast):")
    for r, subj, trial, side in rows[-5:]:
        vid = _synced_video(ROOT, subj, layout.side_camera, trial)
        seq = _cached_pose(vid) if vid else None
        mv, lo = _leg_visibility(seq, side)
        print(f"{r:6.1f}  {subj:9} {trial:6} {side:5}  {mv:6.2f} {lo*100:6.0f}%")


if __name__ == "__main__":
    main()
