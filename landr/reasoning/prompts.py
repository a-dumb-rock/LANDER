"""Prompt construction for the vision-language report layer."""

from __future__ import annotations

import json
from typing import Any

SYSTEM_PROMPT = (
    "You are a sports-medicine assistant that explains jump-landing biomechanics "
    "to coaches, parents, and athletes. You are given objective metrics from an "
    "automated screening (the LANDR system) and must produce a clear, supportive, "
    "non-alarming report.\n\n"
    "Rules:\n"
    "- This is decision-support, NOT a diagnosis. Say so. Recommend a qualified "
    "clinician for anyone flagged elevated risk.\n"
    "- Be specific: reference the actual measured angles and which landing moments "
    "they came from.\n"
    "- Keep it readable for a non-expert. No jargon without a plain-language gloss.\n"
    "- Only recommend drills from the provided list; do not invent medical claims.\n"
    "- Be encouraging. Movement patterns are trainable.\n"
)


def build_user_prompt(
    metrics: dict[str, Any],
    less: dict[str, Any],
    risk: dict[str, Any],
    drills: list[str],
    athlete: dict[str, Any] | None = None,
) -> str:
    """Assemble the structured user prompt sent to the VLM."""
    payload = {
        "athlete_context": athlete or {},
        "risk": risk,
        "automated_LESS": less,
        "key_metrics": {
            "at_initial_contact": metrics["at_initial_contact"],
            "at_lowest_point": metrics["at_lowest_point"],
            "knee_flexion_displacement_deg": metrics["knee_flexion_displacement_deg"],
            "peak_valgus_deg": metrics["peak_valgus_deg"],
            "asymmetry_index": metrics["asymmetry_index"],
        },
        "approved_drills": drills,
    }
    return (
        "Produce a short landing-mechanics screening report with these sections:\n"
        "1. Summary (1-2 sentences, risk level in plain language)\n"
        "2. What we saw (the specific mechanics driving the result)\n"
        "3. What to work on (use ONLY the approved drills)\n"
        "4. Next steps (re-screen timing; see a clinician if elevated)\n\n"
        "Data:\n" + json.dumps(payload, indent=2)
    )
