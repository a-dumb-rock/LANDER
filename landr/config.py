"""Constants: landmark indices, coordinate conventions, and clinical thresholds.

Landmark indexing follows the MediaPipe Pose model (33 landmarks). Keeping the
indices in one place means the rest of the codebase never hard-codes magic numbers.

Coordinate convention used throughout LANDR (after normalization):
    x : left(-)  -> right(+)     image horizontal
    y : up(+)    -> down(-)      we flip image-y so that "up" is positive
    z : toward camera(+) / away(-)  depth (noisy from a single camera)

All angles are in degrees.
"""

from __future__ import annotations

# --- MediaPipe Pose landmark indices -------------------------------------
NOSE = 0
LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_HIP = 23
RIGHT_HIP = 24
LEFT_KNEE = 25
RIGHT_KNEE = 26
LEFT_ANKLE = 27
RIGHT_ANKLE = 28
LEFT_FOOT_INDEX = 31
RIGHT_FOOT_INDEX = 32

NUM_LANDMARKS = 33

# Convenient joint-chain definitions (hip, knee, ankle) per side.
LEG_CHAINS = {
    "left": (LEFT_HIP, LEFT_KNEE, LEFT_ANKLE),
    "right": (RIGHT_HIP, RIGHT_KNEE, RIGHT_ANKLE),
}

# --- Clinical / heuristic thresholds -------------------------------------
# These approximate published Landing Error Scoring System (LESS) criteria.
# They are intentionally centralized and documented so they can be tuned and,
# eventually, replaced by learned parameters (Phase 4).

KNEE_FLEXION_IC_MIN = 30.0
KNEE_FLEXION_DISPLACEMENT_MIN = 45.0
TRUNK_FLEXION_MIN = 15.0
KNEE_VALGUS_DEG = 10.0
ASYMMETRY_INDEX_MAX = 0.15

# --- Risk thresholds ------------------------------------------------------
LESS_HIGH_RISK_THRESHOLD = 5

RISK_BANDS = [
    (0, 3, "low"),
    (4, 5, "moderate"),
    (6, 99, "high"),
]
