"""Full-range flexion gain calibration: fit on TUNE squats, score on TEST drop-jumps.

Doubly-clean generalization test (different SUBJECTS and different TASK):
  FIT  : subject10/11 squats1 (knee flexion spans ~0-110 deg) -> pose_flex vs
         OpenSim knee_angle, lag-aligned -> global gain+offset (the honest slope).
  SCORE: held-out test subjects' DJ trials -> does the frozen squats calibration
         beat the sign+offset baseline against knee_angle?

Pose on the 2 squats videos is cached on first run (~20 min CPU); DJ poses are
already cached, so scoring is fast.
"""

from __future__ import annotations

import os
import numpy as np

from .adapter import DataLayout
from .align import Convention, align_series, fit_convention, rmse
from .benchmark_real import fit_conventions
from .ground_truth import flexion_from_mot
from .opensim_io import read_mot
from .resolve_trials import _synced_video, resolve_all_trials
from .runner import angles_from_video

ROOT = "C:/Users/sagar/opencap_data/LabValidation_withVideos"
CACHE = "C:/Users/sagar/LANDR/validation/pose_cache"
TUNE = ["subject10", "subject11"]
FIT_TRIALS = ["squats1"]


def _squats_fit_pairs(layout):
    P, G = [], []
    for subj in TUNE:
        for trial in FIT_TRIALS:
            vid = _synced_video(ROOT, subj, layout.side_camera, trial)
            ik = os.path.join(ROOT, subj, "OpenSimData", "Mocap", "IK", f"{trial}.mot")
            if not vid or not os.path.exists(ik):
                print(f"  missing {subj}/{trial}"); continue
            print(f"  pose on {subj}/{trial} ...", flush=True)
            ang = angles_from_video(vid, backend="rtmpose", cache_dir=CACHE)
            mot = read_mot(ik)
            for side in ("left", "right"):
                t_ik, gt = flexion_from_mot(mot, side)
                ap = align_series(ang.time, ang.naive["flexion"][side], t_ik, gt,
                                  convention=None, ref_fps=60.0)
                P.append(ap.pred); G.append(ap.gt)
    return np.concatenate(P), np.concatenate(G)


def main() -> None:
    layout = DataLayout(root=ROOT)

    print("Step 1  Fit gain+offset on TUNE squats (full-range) ...")
    P, G = _squats_fit_pairs(layout)
    slope, offset = np.polyfit(P, G, 1)
    corr = float(np.corrcoef(P, G)[0, 1])
    squats_conv = Convention(sign=1.0, scale=float(slope), offset=float(offset))
    print(f"  squats gain fit: knee = {slope:.3f} * pose + {offset:.2f}  (corr {corr:.3f}, "
          f"range {P.min():.0f}-{P.max():.0f} deg)")

    print("\nStep 2  Load held-out TEST drop-jump trials (cached) ...")
    trials = resolve_all_trials(ROOT, layout, backend="rtmpose", verbose=False, cache_dir=CACHE)
    tune_set = set(TUNE)
    test = [t for t in trials if t.subject not in tune_set and t.metric == "flexion"]

    # baseline convention: sign+offset fit on TUNE DJ (reproduces the 25.4 number)
    dj_tune = [t for t in trials if t.subject in tune_set]
    base_conv = fit_conventions(dj_tune)["flexion"]

    def score(conv):
        out = []
        for t in test:
            ap = align_series(t.t_pred, t.y_naive, t.t_gt, t.y_gt, convention=conv, ref_fps=60.0)
            out.append(rmse(ap.pred, ap.gt))
        return np.mean(out), np.median(out), np.max(out)

    b = score(base_conv)
    s = score(squats_conv)
    print("\n=== TEST DJ flexion RMSE vs OpenSim knee_angle (held-out subjects) ===")
    print(f"  baseline sign+offset (tune DJ)      : mean {b[0]:5.2f}  median {b[1]:5.2f}  worst {b[2]:5.2f}"
          f"   [sign={base_conv.sign:+.0f} offset={base_conv.offset:+.2f}]")
    print(f"  squats gain+offset (tune squats)    : mean {s[0]:5.2f}  median {s[1]:5.2f}  worst {s[2]:5.2f}"
          f"   [scale={squats_conv.scale:.3f} offset={squats_conv.offset:+.2f}]")
    print(f"\n  --> improvement: {b[0]-s[0]:+.2f} deg mean ({100*(b[0]-s[0])/b[0]:+.1f}%)")


if __name__ == "__main__":
    main()
