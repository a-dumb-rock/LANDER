"""Two-view (front + side) fusion — the biggest single-camera accuracy win.

A single camera can't see both knee valgus (a frontal-plane motion) and knee/trunk
flexion (a sagittal-plane motion) well at the same time. Filming two clips fixes it:

  * FRONT view  -> trustworthy knee **valgus** and inter-limb **asymmetry**
  * SIDE view   -> trustworthy knee **flexion** and **trunk** flexion

`analyze_two_view` runs the pipeline on each clip and fuses the metrics: valgus from
the front, flexion/trunk from the side. No camera calibration required (unlike full
3D triangulation) — we just take each angle from the view that measures it best.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from .biomechanics import compute_metrics, detect_landing_events
from .reasoning.vlm import generate_report
from .scoring import assess_risk, score_less
from .types import AnalysisResult, PoseSequence


def _resample(values: list[float], src_t: list[float], dst_t: list[float]) -> list[float]:
    """Resample a time series onto a new time grid via linear interpolation."""
    if not values or not src_t:
        return [0.0] * len(dst_t)
    return list(np.interp(dst_t, src_t, values))


def fuse_metrics(front: dict[str, Any], side: dict[str, Any]) -> dict[str, Any]:
    """Combine front-view and side-view metric dicts into one.

    Valgus + asymmetry come from the front; flexion + trunk come from the side.
    Side series are resampled onto the front time grid for clean plotting.
    """
    ft = front["series"]["time_s"]
    st = side["series"]["time_s"]

    series = {
        "time_s": ft,
        # valgus from FRONT (as captured)
        "knee_valgus_left": front["series"]["knee_valgus_left"],
        "knee_valgus_right": front["series"]["knee_valgus_right"],
        # flexion + trunk from SIDE, resampled to the front time grid
        "knee_flexion_left": _resample(side["series"]["knee_flexion_left"], st, ft),
        "knee_flexion_right": _resample(side["series"]["knee_flexion_right"], st, ft),
        "trunk_flexion": _resample(side["series"]["trunk_flexion"], st, ft),
    }

    return {
        "series": series,
        "at_initial_contact": {
            "knee_flexion_deg": side["at_initial_contact"]["knee_flexion_deg"],
            "knee_valgus_deg": front["at_initial_contact"]["knee_valgus_deg"],
            "trunk_flexion_deg": side["at_initial_contact"]["trunk_flexion_deg"],
        },
        "at_lowest_point": {
            "knee_flexion_deg": side["at_lowest_point"]["knee_flexion_deg"],
            "knee_valgus_deg": front["at_lowest_point"]["knee_valgus_deg"],
        },
        "knee_flexion_displacement_deg": side["knee_flexion_displacement_deg"],
        "peak_valgus_deg": front["peak_valgus_deg"],
        "asymmetry_index": front["asymmetry_index"],
        "fusion": {"valgus_from": "front", "flexion_from": "side"},
    }


def analyze_two_view_sequences(
    front_seq: PoseSequence,
    side_seq: PoseSequence,
    athlete: dict[str, Any] | None = None,
    report_provider: str = "mock",
    report_model: str | None = None,
) -> AnalysisResult:
    """Fuse two already-extracted sequences (front + side) into one analysis."""
    ev_front = detect_landing_events(front_seq)
    ev_side = detect_landing_events(side_seq)
    m_front = compute_metrics(front_seq, ev_front)
    m_side = compute_metrics(side_seq, ev_side)
    metrics = fuse_metrics(m_front, m_side)

    less = score_less(metrics)
    risk = assess_risk(less, metrics)
    result = AnalysisResult(
        metrics=metrics, events=ev_front, less=less, risk=risk,
        meta={"athlete": athlete or {}, "mode": "two_view",
              "front": front_seq.meta, "side": side_seq.meta},
    )
    report, provider_used = generate_report(
        result, provider=report_provider, model=report_model, athlete=athlete
    )
    result.report = report
    result.report_provider = provider_used
    return result


def analyze_two_view(
    front_video: str,
    side_video: str,
    athlete: dict[str, Any] | None = None,
    report_provider: str = "mock",
    report_model: str | None = None,
    model_size: str = "full",
    backend: str = "mediapipe",
    refine: bool = True,
) -> AnalysisResult:
    """Run two-view analysis from a front and a side video (requires mediapipe)."""
    from .accuracy import improved_sequence
    from .pose import estimate_from_video

    front = estimate_from_video(front_video, model_size=model_size, backend=backend)
    side = estimate_from_video(side_video, model_size=model_size, backend=backend)
    if refine:
        front, side = improved_sequence(front), improved_sequence(side)
    return analyze_two_view_sequences(
        front, side, athlete=athlete,
        report_provider=report_provider, report_model=report_model,
    )
