"""Corrective-exercise library mapped to LESS item keys.

Used by the mock report generator and offered to the VLM as grounding. Not medical
advice; a coaching aid.
"""

from __future__ import annotations

DRILLS: dict[str, list[str]] = {
    "knee_flexion_at_contact": [
        "Soft-landing drills: cue 'land quietly' and absorb through hips/knees.",
        "Box drop-to-stick landings, progressing height as control improves.",
    ],
    "knee_valgus_at_contact": [
        "Banded squats / lateral band walks to train hip-abductor knee control.",
        "Single-leg balance with a 'knees over toes, not inward' cue.",
    ],
    "knee_valgus_at_lowest": [
        "Tempo squats with a band above the knees to resist medial collapse.",
        "Single-leg Romanian deadlifts for hip/glute strength.",
    ],
    "peak_knee_valgus": [
        "Nordic hamstring curls and glute-med strengthening.",
        "Drop-jump landings filmed for real-time valgus feedback.",
    ],
    "trunk_flexion_at_contact": [
        "Hip-hinge patterning (RDLs, kettlebell deadlifts) to land with trunk flexed.",
        "Cue 'chest over knees' on landing.",
    ],
    "knee_flexion_displacement": [
        "Deeper, slower eccentric landings to build energy absorption.",
        "Squat-depth mobility work (ankle dorsiflexion, hip).",
    ],
    "landing_asymmetry": [
        "Single-leg strength balancing for the weaker side.",
        "Unilateral hop-and-stick drills with symmetry checks.",
    ],
    "overall_impression": [
        "A structured neuromuscular-training program (e.g., FIFA 11+ / PEP-style).",
        "Plyometric progression with landing-technique coaching.",
    ],
}

GENERIC = [
    "Add a 15-20 min neuromuscular warm-up (e.g., FIFA 11+) 2-3x/week.",
    "Re-screen in 6-8 weeks to track change.",
]


def drills_for(error_keys: list[str], max_items: int = 4) -> list[str]:
    """Return a de-duplicated list of drills for the given failed LESS items."""
    out: list[str] = []
    for key in error_keys:
        for d in DRILLS.get(key, []):
            if d not in out:
                out.append(d)
    if not out:
        out = list(GENERIC)
    return out[:max_items]
