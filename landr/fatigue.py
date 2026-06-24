"""Pillar 2 — Fatigue: measure the risk that actually matters.

Injuries happen when athletes are fatigued, but screening is done when they're
fresh. This module compares an athlete's landing mechanics in a FRESH vs a
FATIGUED state and produces a personal *fatigue-vulnerability* signature: how much
their mechanics decay under fatigue.

Why within-athlete change is powerful: comparing an athlete to themselves cancels
most of the per-person measurement bias, so the fatigue signal is more robust than
absolute angles — which also relaxes the accuracy requirement (Pillars 1 & 2
reinforce each other).

The literature this is grounded in: fatigue reduces knee flexion at contact and
increases peak knee valgus (the ACL-injury pattern), and females degrade more.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import Any

from .types import AnalysisResult


@dataclass
class FatigueComparison:
    """Fresh vs fatigued comparison and the resulting vulnerability signature."""

    deltas: dict[str, float]          # change (fatigued - fresh) per metric
    vulnerability_score: float        # 0-100; higher = degrades more under fatigue
    category: str                     # "robust" | "moderate" | "vulnerable"
    fresh_summary: dict[str, Any]
    fatigued_summary: dict[str, Any]
    rationale: str

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _summary(result: AnalysisResult) -> dict[str, Any]:
    m = result.metrics
    return {
        "knee_flexion_at_contact_deg": m["at_initial_contact"]["knee_flexion_deg"],
        "peak_valgus_deg": max(abs(m["peak_valgus_deg"]["left"]),
                               abs(m["peak_valgus_deg"]["right"])),
        "knee_flexion_displacement_deg": m["knee_flexion_displacement_deg"],
        "asymmetry_index": m["asymmetry_index"],
        "less_total": result.less.total,
        "risk_score": result.risk.score_0_100,
    }


def _band(score: float) -> str:
    if score < 25:
        return "robust"
    if score < 55:
        return "moderate"
    return "vulnerable"


def compare(fresh: AnalysisResult, fatigued: AnalysisResult) -> FatigueComparison:
    """Compare a fresh and a fatigued analysis of the same athlete."""
    f, g = _summary(fresh), _summary(fatigued)

    # Deltas in the injury-relevant direction.
    d_valgus = g["peak_valgus_deg"] - f["peak_valgus_deg"]              # +ve = worse
    d_flexion_loss = f["knee_flexion_at_contact_deg"] - g["knee_flexion_at_contact_deg"]  # +ve = worse
    d_absorption_loss = f["knee_flexion_displacement_deg"] - g["knee_flexion_displacement_deg"]  # +ve worse
    d_asym = g["asymmetry_index"] - f["asymmetry_index"]               # +ve = worse
    d_less = g["less_total"] - f["less_total"]

    deltas = {
        "peak_valgus_increase_deg": round(d_valgus, 2),
        "knee_flexion_loss_deg": round(d_flexion_loss, 2),
        "absorption_loss_deg": round(d_absorption_loss, 2),
        "asymmetry_increase": round(d_asym, 3),
        "less_total_increase": int(d_less),
    }

    # Vulnerability score: weighted, clamped to 0-100. Weights chosen so each OLD
    # degradation channel contributes meaningfully; tune / learn later (Phase 4). OLD
    # weighting according to significance of risk
    # exponential method
    score = (
        (max(0.0, d_valgus) ** 1.4) * 0.4
        + max(0.0, d_flexion_loss) * 1.1
        + max(0.0, d_absorption_loss) * 0.8
        + (max(0.0, d_asym) * 25.0)
        + max(0, d_less) * 4.0
    )
    score = float(max(0.0, min(100.0, score)))
    category = _band(score)

    rationale = (
        f"Under fatigue, peak knee valgus changed by {d_valgus:+.1f}°, knee flexion "
        f"at contact by {-d_flexion_loss:+.1f}°, and the automated LESS by {d_less:+d}. "
        f"Fatigue-vulnerability score {score:.0f}/100 ({category})."
    )
    return FatigueComparison(
        deltas=deltas,
        vulnerability_score=round(score, 1),
        category=category,
        fresh_summary=f,
        fatigued_summary=g,
        rationale=rationale,
    )


def fatigue_report(cmp: FatigueComparison, name: str | None = None) -> str:
    """A short plain-language fatigue-vulnerability report (offline)."""
    who = name or "This athlete"
    phrase = {
        "robust": "holds up well under fatigue",
        "moderate": "shows moderate mechanical decay under fatigue",
        "vulnerable": "degrades substantially under fatigue",
    }[cmp.category]
    lines = [
        "# LANDR Fatigue-Vulnerability Report\n",
        f"**Summary.** {who} **{phrase}** "
        f"(fatigue-vulnerability {cmp.vulnerability_score}/100, {cmp.category}). "
        f"This is a screening aid, not a diagnosis.\n",
        "**Fresh vs fatigued change:**",
        f"- Peak knee valgus: {cmp.deltas['peak_valgus_increase_deg']:+}° "
        f"(higher = more medial collapse when tired)",
        f"- Knee flexion at contact: {-cmp.deltas['knee_flexion_loss_deg']:+}° "
        f"(more negative = stiffer landing when tired)",
        f"- Energy absorption (flexion range): "
        f"{-cmp.deltas['absorption_loss_deg']:+}°",
        f"- Inter-limb asymmetry: {cmp.deltas['asymmetry_increase']:+}",
        f"- Automated LESS: {cmp.deltas['less_total_increase']:+} errors",
        "",
        "**Why this matters.** Most screening is done fresh, but ACL injuries often "
        "occur when athletes are fatigued. An athlete who looks fine rested but "
        "degrades sharply when tired is exactly who a single static screen misses.",
        "",
        "**Next steps.**",
    ]
    if cmp.category == "vulnerable":
        lines.append("- Prioritize fatigue-resistant neuromuscular training; "
                     "consider load management late in sessions/season.")
        lines.append("- A movement assessment with a clinician is worthwhile.")
    else:
        lines.append("- Maintain neuromuscular training; re-screen across the season "
                     "to watch the trend.")
    lines.append("\n_Decision-support only. Keep a qualified clinician in the loop._")
    return "\n".join(lines)
