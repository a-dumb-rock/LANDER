"""Does a dedicated STATIC-stand pre-screen improve absolute valgus accuracy?

For each held-out subject: run pose on the front-camera `static1` clip, take the
per-side median valgus as that athlete's neutral baseline, subtract it from their
drop-jump valgus, and re-score vs mocap. This is the realistic version of the
oracle per-subject calibration (which showed 9.0 -> 5.2 deg is *available*). The
within-clip standing frames failed to capture it (drop-jumps start on a box); a
clean dedicated stand is the fair test.
"""

from __future__ import annotations

import os
import numpy as np

from .adapter import DataLayout
from .align import align_series, rmse
from .benchmark_real import fit_conventions, MAX_LAG_S
from .resolve_trials import _synced_video, resolve_all_trials
from .runner import angles_from_video

ROOT = "C:/Users/sagar/opencap_data/LabValidation_withVideos"
CACHE = "C:/Users/sagar/LANDR/validation/pose_cache"
TUNE = {"subject10", "subject11"}


def _static_baseline(subject: str, layout) -> dict[str, float] | None:
    vid = _synced_video(ROOT, subject, layout.front_camera, "static1")
    if not vid:
        return None
    ang = angles_from_video(vid, backend="rtmpose", cache_dir=CACHE)
    return {s: float(np.median(ang.naive["valgus"][s])) for s in ("left", "right")}


def main() -> None:
    layout = DataLayout(root=ROOT)
    trials = resolve_all_trials(ROOT, layout, backend="rtmpose", verbose=False, cache_dir=CACHE)
    conv = fit_conventions([t for t in trials if t.subject in TUNE])["valgus"]

    test_subjects = sorted({t.subject for t in trials if t.subject not in TUNE})
    baselines = {}
    for s in test_subjects:
        print(f"  static pose for {s} ...", flush=True)
        b = _static_baseline(s, layout)
        if b:
            baselines[s] = b
            print(f"    baseline valgus L={b['left']:+.1f} R={b['right']:+.1f} deg")

    base_r, cal_r = [], []
    for t in trials:
        if t.subject in TUNE or t.metric != "valgus" or t.subject not in baselines:
            continue
        pre = baselines[t.subject][t.side]
        a0 = align_series(t.t_pred, t.y_naive, t.t_gt, t.y_gt, convention=conv, ref_fps=60.0, max_lag_s=MAX_LAG_S)
        a1 = align_series(t.t_pred, t.y_naive - pre, t.t_gt, t.y_gt, convention=conv, ref_fps=60.0, max_lag_s=MAX_LAG_S)
        base_r.append(rmse(a0.pred, a0.gt))
        cal_r.append(rmse(a1.pred, a1.gt))

    b, c = np.mean(base_r), np.mean(cal_r)
    print(f"\n=== VALGUS: static pre-screen calibration (held-out subjects) ===")
    print(f"  baseline (no calib)     : {b:.2f} deg")
    print(f"  static-stand calibrated : {c:.2f} deg   ({100*(b-c)/b:+.0f}%)")
    print(f"  (oracle ceiling was 5.2 deg / +42%)")


if __name__ == "__main__":
    main()
