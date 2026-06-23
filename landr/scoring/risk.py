"""Map the automated LESS + raw metrics to a risk category and a 0-100 score.

A transparent, rule-based model for v1. In sports medicine an explainable score
beats a black box, and it gives a baseline to beat with a learned, outcome-
validated model (Phase 4).
"""

from __future__ import annotations

from typing import Any

from .. import config
from ..types import LessResult, RiskResult


def _band(less_total: int) -> str:
    for lo, hi, name in config.RISK_BANDS:
        if lo <= less_total <= hi:
            return name
    return "high"


def assess_risk(less: LessResult, metrics: dict[str, Any]) -> RiskResult:
    """Combine the LESS total with continuous metrics into a risk assessment."""
    category = _band(less.total)

    peak_valgus = max(
        abs(metrics["peak_valgus_deg"]["left"]),
        abs(metrics["peak_valgus_deg"]["right"]),
    )
    base = (less.total / 8.0) * 80.0
    valgus_bonus = min(peak_valgus / 30.0, 1.0) * 20.0
    score = float(max(0.0, min(100.0, base + valgus_bonus)))

    high = less.total >= config.LESS_HIGH_RISK_THRESHOLD
    rationale = (
        f"Automated LESS total = {less.total} "
        f"({'>=' if high else '<'} {config.LESS_HIGH_RISK_THRESHOLD}, the "
        f"literature-associated high-risk threshold). "
        f"Peak knee valgus {peak_valgus:.1f}°. Category: {category}."
    )
    return RiskResult(
        category=category,
        score_0_100=round(score, 1),
        less_total=less.total,
        rationale=rationale,
    )
