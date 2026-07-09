"""End-to-end self-test of the validation harness on SYNTHETIC data.

Proves the mechanics are correct before the real 19 GB download arrives:
  * the .mot/.trc readers round-trip,
  * ground-truth angle computation reuses LANDR geometry,
  * the runner turns a PoseSequence into naive/improved series via LANDR's API,
  * alignment + global-convention fit + subject split + RMSE all work, and
  * the accuracy pass actually reduces flexion error on noisy input.

Run:  python -m validation.selftest
"""

from __future__ import annotations

import os
import tempfile

import numpy as np

from landr.config import LEG_CHAINS, NUM_LANDMARKS
from landr.types import PoseSequence

from .align import Convention, fit_convention
from .benchmark_real import TrialAngles, run_from_trials
from .ground_truth import flexion_from_centers, valgus_from_centers
from .opensim_io import read_mot, read_trc
from .runner import angles_from_sequence


# --------------------------------------------------------------------------- #
# Synthetic skeleton generator (a drop-landing in LANDR convention)
# --------------------------------------------------------------------------- #
def _synthetic_leg(n: int = 90, fps: float = 60.0, seed: int = 0):
    """Return (t, hip, knee, ankle) (T,3) for the RIGHT leg with a landing curve."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / fps
    # flexion curve: 10 -> ~70 -> 45 degrees (a landing then partial rebound)
    phase = np.linspace(0, np.pi, n)
    flex = 10 + 60 * np.sin(phase) ** 2
    flex = 10 + (flex - 10) * (0.75 + 0.25 * rng.random())  # per-subject amplitude
    # small time-varying valgus (medial knee collapse), 0 -> ~12 deg
    valg = 12 * np.sin(phase) ** 2

    Lt = Ls = 0.4
    hip = np.tile(np.array([0.1, 1.0, 0.0]), (n, 1)).astype(float)
    thigh_dir = np.tile(np.array([0.0, -1.0, 0.0]), (n, 1)).astype(float)
    knee = hip + Lt * thigh_dir
    # medial collapse shifts the knee laterally in x (frontal plane)
    knee[:, 0] += -np.sin(np.radians(valg)) * 0.15  # right knee collapses medially (-x)

    th = np.radians(flex)
    shank_dir = np.stack([np.zeros(n), -np.cos(th), np.sin(th)], axis=1)
    ankle = knee + Ls * shank_dir
    return t, flex, valg, hip, knee, ankle


def _pose_from_centers(hip, knee, ankle, fps, noise=0.02, seed=1) -> PoseSequence:
    """Embed right+left leg centres into a 33-landmark PoseSequence with noise."""
    rng = np.random.default_rng(seed)
    n = len(hip)
    lm = np.zeros((n, NUM_LANDMARKS, 3), dtype=float)
    for side, sign in (("right", 1.0), ("left", -1.0)):
        h_i, k_i, a_i = LEG_CHAINS[side]
        # mirror x for the left leg so both legs are physically present
        mir = np.array([sign, 1.0, 1.0])
        lm[:, h_i] = hip * mir
        lm[:, k_i] = knee * mir
        lm[:, a_i] = ankle * mir
    lm += rng.normal(0, noise, lm.shape)
    return PoseSequence(landmarks=lm, fps=fps, meta={"synthetic": True})


# --------------------------------------------------------------------------- #
# Tests
# --------------------------------------------------------------------------- #
def test_readers_roundtrip() -> None:
    tmp = tempfile.mkdtemp(prefix="landr_val_")
    # --- .mot ---
    mot_path = os.path.join(tmp, "ik.mot")
    with open(mot_path, "w", encoding="utf-8") as fh:
        fh.write("Coordinates\nversion=1\nnRows=3\nnColumns=3\ninDegrees=yes\n")
        fh.write("endheader\n")
        fh.write("time\tknee_angle_r\tknee_angle_l\n")
        fh.write("0.0\t10.0\t11.0\n0.1\t40.0\t41.0\n0.2\t20.0\t21.0\n")
    mot = read_mot(mot_path)
    assert mot.has("knee_angle_r"), "knee_angle_r not parsed"
    assert np.allclose(mot.column("knee_angle_r"), [10, 40, 20]), "mot values wrong"
    assert mot.in_degrees is True

    # --- .trc ---
    trc_path = os.path.join(tmp, "markers.trc")
    hdr = ["PathFileType\t4\t(X/Y/Z)\tmarkers.trc",
           "DataRate\tCameraRate\tNumFrames\tNumMarkers\tUnits\tOrigDataRate\tOrigDataStartFrame\tOrigNumFrames",
           "100.0\t100.0\t2\t2\tm\t100.0\t1\t2",
           "Frame#\tTime\tRKNE\t\t\tRANK\t\t",
           "\t\tX1\tY1\tZ1\tX2\tY2\tZ2",
           "",
           "1\t0.00\t0.1\t0.6\t0.0\t0.1\t0.2\t0.0",
           "2\t0.01\t0.1\t0.6\t0.0\t0.1\t0.2\t0.0"]
    with open(trc_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(hdr) + "\n")
    trc = read_trc(trc_path)
    assert trc.marker_names == ["RKNE", "RANK"], f"markers parsed wrong: {trc.marker_names}"
    assert trc.positions.shape == (2, 2, 3), f"trc shape wrong: {trc.positions.shape}"
    assert trc.units == "m"
    print("[ok] readers round-trip (.mot columns, .trc markers)")


def test_ground_truth_matches_landr_geometry() -> None:
    t, flex, valg, hip, knee, ankle = _synthetic_leg()
    gt_flex = flexion_from_centers(hip, knee, ankle)
    # Reconstructed flexion should match the injected curve to sub-degree: the
    # tiny residual is the lateral valgus knee-shift coupling into the 3D angle.
    err = float(np.sqrt(np.mean((gt_flex - flex) ** 2)))
    assert err < 0.2, f"GT flexion does not match injected flexion: RMSE={err}"
    gt_valg = valgus_from_centers(hip, knee, ankle, "right")
    assert np.all(np.isfinite(gt_valg)) and np.max(np.abs(gt_valg)) > 1.0, "valgus GT looks wrong"
    print(f"[ok] ground truth reuses LANDR geometry (flexion recon RMSE={err:.2e}deg, "
          f"peak valgus={np.max(np.abs(gt_valg)):.1f}deg)")


def test_runner_produces_series() -> None:
    t, flex, valg, hip, knee, ankle = _synthetic_leg()
    seq = _pose_from_centers(hip, knee, ankle, fps=60.0, noise=0.02)
    ang = angles_from_sequence(seq)
    assert set(ang.naive) == {"valgus", "flexion"}
    assert ang.naive["flexion"]["right"].shape == flex.shape
    print(f"[ok] runner: naive+improved series via LANDR API "
          f"({ang.naive['flexion']['right'].shape[0]} frames)")


def test_end_to_end_benchmark_reduces_error() -> None:
    """Full pipeline on 2 synthetic subjects; improved must beat naive on flexion."""
    all_trials: list[TrialAngles] = []
    for si, subj in enumerate(["subjA", "subjB"]):
        t, flex, valg, hip, knee, ankle = _synthetic_leg(seed=si)
        seq = _pose_from_centers(hip, knee, ankle, fps=60.0, noise=0.03, seed=si + 10)
        ang = angles_from_sequence(seq)

        # GT from clean centres; inject a deliberate sign+offset the fit must recover
        gt_flex = -flexion_from_centers(hip, knee, ankle) + 7.0   # sign=-1, offset=+7
        gt_valg = valgus_from_centers(hip, knee, ankle, "right")

        all_trials.append(TrialAngles(
            subject=subj, trial="DJ1", metric="flexion", side="right", fps=60.0,
            t_pred=ang.time, y_naive=ang.naive["flexion"]["right"],
            y_improved=ang.improved["flexion"]["right"], t_gt=t, y_gt=gt_flex,
        ))
        all_trials.append(TrialAngles(
            subject=subj, trial="DJ1", metric="valgus", side="right", fps=60.0,
            t_pred=ang.time, y_naive=ang.naive["valgus"]["right"],
            y_improved=ang.improved["valgus"]["right"], t_gt=t, y_gt=gt_valg,
        ))

    report = run_from_trials(all_trials, tune_subjects=["subjA"])
    summ = report.summary()

    # convention recovery: flexion sign must be -1 (we injected a flip)
    assert report.conventions["flexion"].sign == -1.0, "convention did not recover sign flip"
    assert abs(report.conventions["flexion"].offset - 7.0) < 3.0, "offset off"

    fx = summ["per_metric"]["flexion"]
    assert fx["improved_rmse_deg"] <= fx["naive_rmse_deg"] + 1e-6, (
        f"accuracy pass did NOT reduce flexion error: {fx}"
    )
    assert summ["test_subjects"] == ["subjB"], "subject leak: test set wrong"
    print(f"[ok] end-to-end: convention={report.conventions['flexion']}, "
          f"flexion naive={fx['naive_rmse_deg']}deg -> improved={fx['improved_rmse_deg']}deg "
          f"({fx['reduction_pct']}% reduction), test={summ['test_subjects']}")
    return summ


def main() -> None:
    print("Running LANDR validation-harness self-test (synthetic data)\n" + "-" * 60)
    test_readers_roundtrip()
    test_ground_truth_matches_landr_geometry()
    test_runner_produces_series()
    summ = test_end_to_end_benchmark_reduces_error()
    print("-" * 60)
    print("ALL SELF-TESTS PASSED. Harness mechanics are correct.")
    print("Waiting on real data: unzip OpenCap, then run `python -m validation.discover_cli <root>`.")


if __name__ == "__main__":
    main()
