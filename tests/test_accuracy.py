"""Tests for the accuracy module (Pillar 1)."""

import numpy as np

from landr.accuracy import (
    angle_rmse,
    enforce_limb_lengths,
    run_accuracy_benchmark,
    temporal_smooth,
)
from landr import config
from landr.synthetic import synthetic_jump


def test_angle_rmse_zero_for_identical():
    a = np.array([1.0, 2.0, 3.0])
    assert angle_rmse(a, a) == 0.0


def test_limb_constraint_makes_lengths_constant():
    seq = synthetic_jump(quality="poor", seed=0, noise=0.05)
    fixed = enforce_limb_lengths(seq.landmarks)
    hip, knee, _ = config.LEG_CHAINS["left"]
    lengths = np.linalg.norm(fixed[:, knee] - fixed[:, hip], axis=1)
    assert lengths.std() < 1e-6  # thigh length now constant


def test_temporal_smooth_reduces_variance():
    seq = synthetic_jump(quality="poor", seed=0, noise=0.05)
    raw = seq.landmarks
    sm = temporal_smooth(raw)
    # smoothed signal should have lower frame-to-frame jitter
    assert np.mean(np.abs(np.diff(sm, axis=0))) < np.mean(np.abs(np.diff(raw, axis=0)))


def test_benchmark_improves_accuracy():
    res = run_accuracy_benchmark(noise_std=0.03, seed=0)
    for which in ("valgus", "flexion"):
        assert res[which]["improved_rmse_deg"] <= res[which]["naive_rmse_deg"]
    # Expect a meaningful valgus improvement.
    assert res["valgus"]["reduction_pct"] > 0
