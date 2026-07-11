"""Associate multi-person detections across calibrated views (epipolar matching).

The Studio motion-camera vision is to handle scenes with several athletes at once
(e.g. a whole drill). When each camera detects K people, we must decide which
detection in camera A corresponds to which in camera B *before* triangulating —
otherwise we'd triangulate one person's knee against another's.

We use the epipolar constraint: a point seen in camera A must lie on its epipolar
line in camera B. For a candidate pairing we score the symmetric epipolar distance
across shared keypoints; low distance = same physical person. We then greedily match
people across views and triangulate each matched group.

This is standard multi-view geometry (fundamental matrix from calibrated cameras),
no learning. It is validated synthetically with two people in
``python -m studio.selftest``.
"""

from __future__ import annotations

import numpy as np

from .calibration import Camera

_EPS = 1e-9


def _skew(t: np.ndarray) -> np.ndarray:
    return np.array([[0, -t[2], t[1]], [t[2], 0, -t[0]], [-t[1], t[0], 0]], float)


def fundamental_matrix(cam_a: Camera, cam_b: Camera) -> np.ndarray:
    """Fundamental matrix F mapping a point in A to its epipolar line in B.

    For x_b^T F x_a = 0. Derived from the calibrated relative pose:
    E = [t_ba]_x R_ba,  F = K_b^-T E K_a^-1.
    """
    R_ba = cam_b.R @ cam_a.R.T
    t_ba = cam_b.t - R_ba @ cam_a.t
    E = _skew(t_ba) @ R_ba
    F = np.linalg.inv(cam_b.K).T @ E @ np.linalg.inv(cam_a.K)
    return F


def _epipolar_distance(F: np.ndarray, xa: np.ndarray, xb: np.ndarray) -> float:
    """Symmetric point-to-epipolar-line distance for a correspondence (pixels)."""
    xa_h = np.append(xa, 1.0)
    xb_h = np.append(xb, 1.0)
    lb = F @ xa_h  # epipolar line in B
    la = F.T @ xb_h  # epipolar line in A
    db = abs(xb_h @ lb) / (np.hypot(lb[0], lb[1]) + _EPS)
    da = abs(xa_h @ la) / (np.hypot(la[0], la[1]) + _EPS)
    return 0.5 * (da + db)


def person_match_cost(
    F: np.ndarray,
    kp_a: np.ndarray,
    kp_b: np.ndarray,
    conf_a: np.ndarray,
    conf_b: np.ndarray,
    min_conf: float = 0.2,
) -> float:
    """Mean epipolar distance over keypoints both views see confidently."""
    dists = []
    for ja in range(kp_a.shape[0]):
        if conf_a[ja] < min_conf or conf_b[ja] < min_conf:
            continue
        if not (np.all(np.isfinite(kp_a[ja])) and np.all(np.isfinite(kp_b[ja]))):
            continue
        dists.append(_epipolar_distance(F, kp_a[ja], kp_b[ja]))
    return float(np.mean(dists)) if dists else np.inf


def associate_two_views(
    cam_a: Camera,
    cam_b: Camera,
    people_a: np.ndarray,
    people_b: np.ndarray,
    conf_a: np.ndarray,
    conf_b: np.ndarray,
    max_epipolar_px: float = 30.0,
) -> list[tuple[int, int]]:
    """Greedily match people between two views by epipolar consistency.

    people_a : (Ka, J, 2), people_b : (Kb, J, 2). Returns list of (ia, ib) matches.
    """
    F = fundamental_matrix(cam_a, cam_b)
    Ka, Kb = people_a.shape[0], people_b.shape[0]
    cost = np.full((Ka, Kb), np.inf)
    for ia in range(Ka):
        for ib in range(Kb):
            cost[ia, ib] = person_match_cost(
                F, people_a[ia], people_b[ib], conf_a[ia], conf_b[ib]
            )

    matches: list[tuple[int, int]] = []
    used_b: set[int] = set()
    for ia in np.argsort(cost.min(axis=1)):
        order = np.argsort(cost[ia])
        for ib in order:
            if ib in used_b:
                continue
            if cost[ia, ib] <= max_epipolar_px:
                matches.append((int(ia), int(ib)))
                used_b.add(int(ib))
            break
    return matches
