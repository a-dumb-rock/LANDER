"""Compute per-frame and event-based biomechanical metrics from a PoseSequence."""

from __future__ import annotations

from typing import Any

import numpy as np

from .. import config
from ..types import LandingEvents, PoseSequence
from .geometry import (
    flexion_angle,
    signed_knee_valgus,
    smooth,
    trunk_flexion_from_vertical,
)


def _series_knee_flexion(seq: PoseSequence, side: str) -> np.ndarray:
    hip_i, knee_i, ankle_i = config.LEG_CHAINS[side]
    out = np.array(
        [
            flexion_angle(seq.point(f, hip_i), seq.point(f, knee_i), seq.point(f, ankle_i))
            for f in range(seq.n_frames)
        ]
    )
    return smooth(out, window=5)


def _series_knee_valgus(seq: PoseSequence, side: str) -> np.ndarray:
    hip_i, knee_i, ankle_i = config.LEG_CHAINS[side]
    out = np.array(
        [
            signed_knee_valgus(seq.point(f, hip_i), seq.point(f, knee_i), seq.point(f, ankle_i), side)
            for f in range(seq.n_frames)
        ]
    )
    return smooth(out, window=5)


def _series_trunk_flexion(seq: PoseSequence) -> np.ndarray:
    sh = seq.landmarks[:, [config.LEFT_SHOULDER, config.RIGHT_SHOULDER], :].mean(axis=1)
    hp = seq.landmarks[:, [config.LEFT_HIP, config.RIGHT_HIP], :].mean(axis=1)
    out = np.array([trunk_flexion_from_vertical(sh[f], hp[f]) for f in range(seq.n_frames)])
    return smooth(out, window=5)


def compute_metrics(seq: PoseSequence, events: LandingEvents) -> dict[str, Any]:
    """Return a dict of time-series and event-sampled biomechanical metrics."""
    ic = events.initial_contact
    low = events.lowest_point

    series = {
        "knee_flexion": {"left": _series_knee_flexion(seq, "left"), "right": _series_knee_flexion(seq, "right")},
        "knee_valgus": {"left": _series_knee_valgus(seq, "left"), "right": _series_knee_valgus(seq, "right")},
        "trunk_flexion": _series_trunk_flexion(seq),
    }

    def at(arr: np.ndarray, frame: int) -> float:
        frame = int(np.clip(frame, 0, len(arr) - 1))
        return float(arr[frame])

    kf_ic = np.mean([at(series["knee_flexion"][s], ic) for s in ("left", "right")])
    kf_low = np.mean([at(series["knee_flexion"][s], low) for s in ("left", "right")])
    kv_ic = np.mean([abs(at(series["knee_valgus"][s], ic)) for s in ("left", "right")])
    kv_low = np.mean([abs(at(series["knee_valgus"][s], low)) for s in ("left", "right")])
    trunk_ic = at(series["trunk_flexion"], ic)

    def peak_signed(arr: np.ndarray) -> float:
        return float(arr[int(np.argmax(np.abs(arr)))])

    peak_valgus = {s: peak_signed(series["knee_valgus"][s]) for s in ("left", "right")}

    # --- START OF ADDED ASSESSMENT LOGIC ---
    # Determine the worst inward collapse recorded across both knees
    max_valgus_angle = max(abs(peak_valgus["left"]), abs(peak_valgus["right"]))
    
    # Evaluate risk categorization based on clinical research thresholds
    if max_valgus_angle >= 10.0:
        risk_level = "HIGH RISK"
        recommendation = "High knee valgus detected. Focus on glute medius activation and landing softly."
    elif max_valgus_angle >= 5.0:
        risk_level = "MODERATE RISK"
        recommendation = "Slight inward knee collapse. Monitor hip stability during fatigue."
    else:
        risk_level = "LOW RISK"
        recommendation = "Excellent alignment. Mechanics look safe!"
    # --- END OF ADDED ASSESSMENT LOGIC ---

    pf_l = float(np.max(series["knee_flexion"]["left"]))
    pf_r = float(np.max(series["knee_flexion"]["right"]))
    denom = (pf_l + pf_r) / 2.0 + 1e-6
    asymmetry = abs(pf_l - pf_r) / denom

    return {
        "series": {
            "time_s": seq.time().tolist(),
            "knee_flexion_left": series["knee_flexion"]["left"].tolist(),
            "knee_flexion_right": series["knee_flexion"]["right"].tolist(),
            "knee_valgus_left": series["knee_valgus"]["left"].tolist(),
            "knee_valgus_right": series["knee_valgus"]["right"].tolist(),
            "trunk_flexion": series["trunk_flexion"].tolist(),
        },
        "at_initial_contact": {
            "knee_flexion_deg": round(kf_ic, 2),
            "knee_valgus_deg": round(kv_ic, 2),
            "trunk_flexion_deg": round(trunk_ic, 2),
        },
        "at_lowest_point": {
            "knee_flexion_deg": round(kf_low, 2),
            "knee_valgus_deg": round(kv_low, 2),
        },
        "knee_flexion_displacement_deg": round(kf_low - kf_ic, 2),
        "peak_valgus_deg": {k: round(v, 2) for k, v in peak_valgus.items()},
        "asymmetry_index": round(float(asymmetry), 3),
        
        # --- NEW ASSESSMENT OUTPUT BLOCK ---
        "acl_risk_assessment": {
            "max_valgus_observed_deg": round(max_valgus_angle, 2),
            "risk_factor": risk_level,
            "coaching_cue": recommendation
        }
        # --- END OF NEW ASSESSMENT OUTPUT BLOCK ---
    }