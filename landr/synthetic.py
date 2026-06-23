"""Generate synthetic drop-vertical-jump PoseSequences.

Lets the whole pipeline run and be tested without any video or model download.
Supports a ``fatigue`` knob (for the fatigue module) and a ``noise`` knob (so the
accuracy benchmark can request a clean ground-truth sequence).
"""

from __future__ import annotations

import numpy as np

from . import config
from .types import PoseSequence


def _base_skeleton() -> np.ndarray:
    pts = np.zeros((config.NUM_LANDMARKS, 3), dtype=float)
    pts[config.NOSE] = (0.0, 1.70, 0.0)
    pts[config.LEFT_SHOULDER] = (-0.20, 1.45, 0.0)
    pts[config.RIGHT_SHOULDER] = (0.20, 1.45, 0.0)
    pts[config.LEFT_HIP] = (-0.12, 0.95, 0.0)
    pts[config.RIGHT_HIP] = (0.12, 0.95, 0.0)
    pts[config.LEFT_KNEE] = (-0.12, 0.50, 0.0)
    pts[config.RIGHT_KNEE] = (0.12, 0.50, 0.0)
    pts[config.LEFT_ANKLE] = (-0.12, 0.08, 0.0)
    pts[config.RIGHT_ANKLE] = (0.12, 0.08, 0.0)
    pts[config.LEFT_FOOT_INDEX] = (-0.12, 0.0, 0.10)
    pts[config.RIGHT_FOOT_INDEX] = (0.12, 0.0, 0.10)
    return pts


def synthetic_jump(
    quality: str = "poor",
    fps: int = 60,
    duration_s: float = 1.6,
    seed: int | None = 0,
    fatigue: float = 0.0,
    noise: float = 0.002,
) -> PoseSequence:
    """Create a synthetic landing.

    Parameters
    ----------
    quality : {'good', 'poor'}
        'good' = deep, soft, aligned landing (low risk).
        'poor' = stiff, upright, valgus-collapse landing (high risk).
    fatigue : float in [0, 1]
        How fatigued the athlete is. 0 = fresh. Higher values push mechanics
        toward the injury pattern (less knee flexion, more valgus, more
        asymmetry) — this is how we simulate fatigue-induced degradation. A fresh
        'good' athlete becomes progressively riskier as fatigue rises.
    noise : float
        Std-dev of per-landmark positional noise (mimics pose jitter). Set to 0.0
        for a clean ground-truth sequence (used by the accuracy benchmark).
    """
    rng = np.random.default_rng(seed)
    n = int(fps * duration_s)
    t = np.linspace(0, 1, n)

    center = 0.58
    depth = np.exp(-((t - center) ** 2) / (2 * 0.10**2))
    depth = depth / depth.max()

    if quality == "good":
        max_squat = 0.42
        knee_anterior = 0.34
        valgus_gain = 0.01
        trunk_lean_gain = 0.22
        asym = 0.0
    else:  # 'poor'
        max_squat = 0.16
        knee_anterior = 0.10
        valgus_gain = 0.085
        trunk_lean_gain = 0.03
        asym = 0.35

    # Apply fatigue: degrade mechanics toward the injury pattern.
    f = float(np.clip(fatigue, 0.0, 1.0))
    max_squat *= (1.0 - 0.45 * f)
    knee_anterior *= (1.0 - 0.45 * f)
    valgus_gain += 0.07 * f
    trunk_lean_gain *= (1.0 - 0.5 * f)
    asym += 0.25 * f

    seq = np.zeros((n, config.NUM_LANDMARKS, 3), dtype=float)
    base = _base_skeleton()

    for fr in range(n):
        pts = base.copy()
        d = depth[fr]
        drop = max_squat * d
        for idx in (config.NOSE, config.LEFT_SHOULDER, config.RIGHT_SHOULDER,
                    config.LEFT_HIP, config.RIGHT_HIP):
            pts[idx, 1] -= drop

        knee_drop = drop * 0.55
        for side, knee_i, hip_i, ankle_i, sign in (
            ("left", config.LEFT_KNEE, config.LEFT_HIP, config.LEFT_ANKLE, +1),
            ("right", config.RIGHT_KNEE, config.RIGHT_HIP, config.RIGHT_ANKLE, -1),
        ):
            side_asym = (1.0 + asym) if side == "left" else (1.0 - asym)
            pts[knee_i, 1] -= knee_drop * side_asym
            pts[knee_i, 2] += knee_anterior * d * side_asym
            pts[knee_i, 0] += sign * valgus_gain * d * side_asym

        for idx in (config.LEFT_SHOULDER, config.RIGHT_SHOULDER, config.NOSE):
            pts[idx, 2] += trunk_lean_gain * d

        if noise > 0:
            pts += rng.normal(0, noise, pts.shape)
        seq[fr] = pts

    return PoseSequence(
        landmarks=seq,
        fps=float(fps),
        meta={
            "source": f"synthetic:{quality}:fatigue={f:.2f}",
            "estimator": "synthetic",
            "quality": quality,
            "fatigue": f,
            "fps": float(fps),
        },
    )
