"""Automated Landing Error Scoring System (LESS).

A faithful approximation of the clinician-scored LESS, implementing the subset of
items reliably computable from extracted joint angles. Each item is transparent
(carries its measured value + threshold) so results are auditable and the
thresholds (config.py) can later be replaced by learned parameters.
"""

from __future__ import annotations

from typing import Any

from .. import config
from ..types import LessItem, LessResult


def score_less(metrics: dict[str, Any]) -> LessResult:
    """Score the automated LESS from the metrics dict produced by `compute_metrics`."""
    ic = metrics["at_initial_contact"]
    low = metrics["at_lowest_point"]
    disp = metrics["knee_flexion_displacement_deg"]
    peak_valgus = metrics["peak_valgus_deg"]
    asym = metrics["asymmetry_index"]

    items: list[LessItem] = []

    items.append(LessItem(
        "knee_flexion_at_contact",
        "Insufficient knee flexion at initial contact (stiff landing)",
        ic["knee_flexion_deg"] < config.KNEE_FLEXION_IC_MIN,
        ic["knee_flexion_deg"],
        f"{ic['knee_flexion_deg']}° vs min {config.KNEE_FLEXION_IC_MIN}°",
    ))
    items.append(LessItem(
        "knee_valgus_at_contact",
        "Knee valgus (medial collapse) at initial contact",
        ic["knee_valgus_deg"] > config.KNEE_VALGUS_DEG,
        ic["knee_valgus_deg"],
        f"{ic['knee_valgus_deg']}° vs max {config.KNEE_VALGUS_DEG}°",
    ))
    items.append(LessItem(
        "trunk_flexion_at_contact",
        "Upright trunk at initial contact (insufficient trunk flexion)",
        ic["trunk_flexion_deg"] < config.TRUNK_FLEXION_MIN,
        ic["trunk_flexion_deg"],
        f"{ic['trunk_flexion_deg']}° vs min {config.TRUNK_FLEXION_MIN}°",
    ))
    items.append(LessItem(
        "knee_flexion_displacement",
        "Small knee-flexion range (poor energy absorption)",
        disp < config.KNEE_FLEXION_DISPLACEMENT_MIN,
        disp,
        f"{disp}° vs min {config.KNEE_FLEXION_DISPLACEMENT_MIN}°",
    ))
    items.append(LessItem(
        "knee_valgus_at_lowest",
        "Knee valgus at lowest point (peak medial loading)",
        low["knee_valgus_deg"] > config.KNEE_VALGUS_DEG,
        low["knee_valgus_deg"],
        f"{low['knee_valgus_deg']}° vs max {config.KNEE_VALGUS_DEG}°",
    ))

    max_peak_valgus = max(abs(peak_valgus["left"]), abs(peak_valgus["right"]))
    items.append(LessItem(
        "peak_knee_valgus",
        "Excessive peak knee valgus during landing (either leg)",
        max_peak_valgus > config.KNEE_VALGUS_DEG,
        round(max_peak_valgus, 2),
        f"peak {round(max_peak_valgus, 2)}° vs max {config.KNEE_VALGUS_DEG}°",
    ))
    items.append(LessItem(
        "landing_asymmetry",
        "Asymmetric landing between legs",
        asym > config.ASYMMETRY_INDEX_MAX,
        asym,
        f"index {asym} vs max {config.ASYMMETRY_INDEX_MAX}",
    ))

    poor_global = (
        ic["knee_flexion_deg"] < config.KNEE_FLEXION_IC_MIN
        and max_peak_valgus > config.KNEE_VALGUS_DEG
    )
    items.append(LessItem(
        "overall_impression",
        "Poor overall landing pattern (stiff and valgus)",
        poor_global,
        None,
        "composite of stiffness + valgus",
    ))

    total = sum(1 for it in items if it.error)
    return LessResult(items=items, total=total)
