"""Rotate a triangulated 3D pose into the athlete's anatomical frame.

Once joints are in true 3D world coordinates, we express them in a body-centred
frame so the existing clinical engine measures angles correctly:

    x = medio-lateral  (+x = athlete's RIGHT, from the pelvis line)
    y = vertical        (+y = up, from the rig's known gravity direction)
    z = anterior        (+z = forward, completing a right-handed frame)

Why this matters: LANDR's frontal-plane valgus (``signed_knee_valgus``) computes the
knee's deviation in the x-y plane. In a *single camera* that plane is the image
plane, so any out-of-plane orientation corrupts the angle. Here, x-y is the true
anatomical frontal plane, so the same function now yields the real frontal-plane
projection angle. Knee flexion uses a full-3D vector angle and is frame-independent.

The frame is a single constant rotation per trial, built from the *mean* pelvis
orientation over the clip. It is derived only from the athlete's own geometry and
the rig's up-vector — nothing is fit to ground-truth angles, so it cannot inflate
accuracy.
"""

from __future__ import annotations

import numpy as np

from landr import config
from landr.types import PoseSequence

_EPS = 1e-9


def anatomical_rotation(seq: PoseSequence, up: np.ndarray) -> np.ndarray:
    """Return the 3x3 rotation mapping world coordinates -> anatomical frame.

    up : world up-vector (from the rig calibration).
    """
    up = np.asarray(up, float)
    v = up / (np.linalg.norm(up) + _EPS)  # vertical (+y)

    lm = seq.landmarks
    l_hip = lm[:, config.LEFT_HIP, :]
    r_hip = lm[:, config.RIGHT_HIP, :]
    # Mean medio-lateral axis: left hip -> right hip, averaged over the clip.
    m0 = (r_hip - l_hip).mean(axis=0)
    # Orthogonalise against vertical so x lies in the horizontal (transverse) plane.
    m = m0 - np.dot(m0, v) * v
    if np.linalg.norm(m) < _EPS:
        # Degenerate (hips stacked vertically in view) — pick any axis ⟂ up.
        seed = np.array([1.0, 0.0, 0.0])
        if abs(np.dot(seed, v)) > 0.9:
            seed = np.array([0.0, 1.0, 0.0])
        m = seed - np.dot(seed, v) * v
    x = m / (np.linalg.norm(m) + _EPS)  # medio-lateral (+x = athlete right)
    z = np.cross(x, v)  # anterior (+z = forward), right-handed
    z = z / (np.linalg.norm(z) + _EPS)
    y = np.cross(z, x)  # re-orthogonalise vertical
    R = np.stack([x, y, z], axis=0)  # rows map world vec -> anatomical components
    return R


def to_anatomical(seq: PoseSequence, up: np.ndarray) -> PoseSequence:
    """Return a copy of ``seq`` with landmarks expressed in the anatomical frame.

    Translation is removed (origin = mean pelvis) — it does not affect any angle,
    but it keeps the coordinates centred for visualisation.
    """
    R = anatomical_rotation(seq, up)
    lm = seq.landmarks
    hip_mid = 0.5 * (lm[:, config.LEFT_HIP, :] + lm[:, config.RIGHT_HIP, :])
    origin = hip_mid.mean(axis=0)
    centred = lm - origin  # (T,J,3)
    rotated = centred @ R.T  # apply R to every point
    meta = dict(seq.meta)
    meta["frame"] = "anatomical"
    return PoseSequence(
        landmarks=rotated,
        fps=seq.fps,
        visibility=seq.visibility,
        meta=meta,
    )
