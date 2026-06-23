"""Detect the key frames of a drop-vertical-jump landing."""

from __future__ import annotations

import numpy as np

from .. import config
from ..types import LandingEvents, PoseSequence
from .geometry import smooth


def _vertical_center(seq: PoseSequence) -> np.ndarray:
    hips = seq.landmarks[:, [config.LEFT_HIP, config.RIGHT_HIP], 1]
    return smooth(hips.mean(axis=1), window=5)


def detect_landing_events(seq: PoseSequence) -> LandingEvents:
    """Return :class:`LandingEvents` inferred from the hip vertical trajectory."""
    n = seq.n_frames
    if n < 3:
        return LandingEvents(0, max(0, n - 1), max(0, n - 1), notes="too few frames")

    hip_y = _vertical_center(seq)
    lowest = int(np.argmin(hip_y))
    vel = np.gradient(hip_y)

    # Initial contact ≈ impact moment: fastest downward motion before the lowest
    # point. By this frame some flexion has developed (the moment load hits).
    if lowest >= 1:
        ic = int(np.argmin(vel[: lowest + 1]))
    else:
        ic = 0
    ic = int(min(ic, max(0, lowest - 1)))

    # Stabilized: after the lowest point, first frame where motion settles.
    stab = n - 1
    post = hip_y[lowest:]
    if post.size > 2:
        post_vel = np.abs(np.gradient(post))
        small = post_vel < (0.2 * (post_vel.max() + 1e-9))
        for i in range(1, len(small)):
            if small[i] and small[max(0, i - 1)]:
                stab = lowest + i
                break

    return LandingEvents(
        initial_contact=ic,
        lowest_point=lowest,
        stabilized=stab,
        notes="auto-detected from hip vertical trajectory",
    )
