"""Multi-view triangulation: 2D keypoints from N cameras -> one 3D joint.

This is the geometric heart of Studio. For a single 3D point seen in several
cameras, each observation ``x_i = P_i X`` gives two linear equations in the unknown
``X``; stacking them and solving the homogeneous least-squares (SVD) recovers ``X``.
This is the linear DLT triangulation. We optionally:

  * weight each view's equations by its keypoint confidence, so a poorly-seen joint
    (occluded, low RTMPose score) contributes less; and
  * run a light RANSAC over views to reject a single grossly-wrong detection
    (e.g. left/right swap in one camera) before the final weighted solve.

No learning, no fitting to angles — this is exact geometry. With clean 2D and good
calibration it recovers X to numerical precision; that is what the self-test proves.
"""

from __future__ import annotations

from typing import Sequence

import numpy as np

from .calibration import Camera

_EPS = 1e-9


def triangulate_point(
    cameras: Sequence[Camera],
    points_2d: np.ndarray,
    weights: np.ndarray | None = None,
) -> np.ndarray:
    """Triangulate one 3D point from its 2D observations across cameras.

    cameras   : length-M sequence of calibrated cameras.
    points_2d : (M, 2) pixel observations, one per camera.
    weights   : optional (M,) per-view weights (e.g. keypoint confidence).

    Returns the (3,) world point. Views with weight ~0 are ignored.
    """
    pts = np.asarray(points_2d, float)
    m = len(cameras)
    if weights is None:
        weights = np.ones(m)
    weights = np.asarray(weights, float)

    rows = []
    for cam, (u, v), w in zip(cameras, pts, weights):
        if w <= _EPS or not np.all(np.isfinite([u, v])):
            continue
        P = cam.P
        sw = np.sqrt(w)
        rows.append(sw * (u * P[2] - P[0]))
        rows.append(sw * (v * P[2] - P[1]))
    if len(rows) < 4:  # need >= 2 usable views
        return np.array([np.nan, np.nan, np.nan])

    A = np.array(rows)
    _, _, Vt = np.linalg.svd(A)
    Xh = Vt[-1]
    if abs(Xh[3]) < _EPS:
        return np.array([np.nan, np.nan, np.nan])
    return Xh[:3] / Xh[3]


def _reprojection_errors(
    cameras: Sequence[Camera], points_2d: np.ndarray, X: np.ndarray
) -> np.ndarray:
    """Per-view reprojection error (pixels) of a candidate 3D point."""
    errs = np.full(len(cameras), np.inf)
    for i, (cam, obs) in enumerate(zip(cameras, points_2d)):
        if not np.all(np.isfinite(obs)):
            continue
        proj = cam.project(X.reshape(1, 3))[0]
        errs[i] = float(np.linalg.norm(proj - obs))
    return errs


def triangulate_point_robust(
    cameras: Sequence[Camera],
    points_2d: np.ndarray,
    weights: np.ndarray | None = None,
    ransac_thresh_px: float = 12.0,
    min_conf: float = 0.2,
) -> tuple[np.ndarray, np.ndarray]:
    """Triangulate with a light RANSAC over views to reject outlier detections.

    Returns ``(X, inlier_mask)``. Strategy: try every pair of confident views as a
    minimal hypothesis, score inliers by reprojection error against all views, then
    refit a weighted solve on the largest inlier set. Falls back to the plain
    weighted solve if fewer than two confident views exist.
    """
    pts = np.asarray(points_2d, float)
    m = len(cameras)
    if weights is None:
        weights = np.ones(m)
    weights = np.asarray(weights, float)

    usable = [
        i for i in range(m) if weights[i] >= min_conf and np.all(np.isfinite(pts[i]))
    ]
    if len(usable) < 2:
        X = triangulate_point(cameras, pts, weights)
        mask = np.zeros(m, bool)
        return X, mask

    best_inliers: list[int] = []
    for ai in range(len(usable)):
        for bi in range(ai + 1, len(usable)):
            i, j = usable[ai], usable[bi]
            Xh = triangulate_point([cameras[i], cameras[j]], pts[[i, j]])
            if not np.all(np.isfinite(Xh)):
                continue
            errs = _reprojection_errors(cameras, pts, Xh)
            inliers = [k for k in usable if errs[k] <= ransac_thresh_px]
            if len(inliers) > len(best_inliers):
                best_inliers = inliers

    if len(best_inliers) < 2:
        best_inliers = usable

    mask = np.zeros(m, bool)
    mask[best_inliers] = True
    w = weights.copy()
    w[~mask] = 0.0
    X = triangulate_point(cameras, pts, w)
    return X, mask


def triangulate_sequence(
    cameras: Sequence[Camera],
    keypoints_2d: np.ndarray,
    confidences: np.ndarray | None = None,
    robust: bool = True,
) -> tuple[np.ndarray, np.ndarray]:
    """Triangulate a whole multi-view sequence into a 3D landmark trajectory.

    keypoints_2d : (M, T, J, 2) — per camera, per frame, per joint pixel coords.
    confidences  : (M, T, J) optional per-keypoint confidence in [0,1].
    robust       : run per-joint RANSAC over views (slower, rejects bad detections).

    Returns ``(points_3d, conf_3d)`` where points_3d is (T, J, 3) world coordinates
    and conf_3d is (T, J) the mean confidence of the views used.
    """
    kp = np.asarray(keypoints_2d, float)
    M, T, J, _ = kp.shape
    if confidences is None:
        confidences = np.ones((M, T, J))
    conf = np.asarray(confidences, float)

    out = np.zeros((T, J, 3))
    out_conf = np.zeros((T, J))
    for t in range(T):
        for j in range(J):
            obs = kp[:, t, j, :]  # (M,2)
            w = conf[:, t, j]  # (M,)
            if robust:
                X, mask = triangulate_point_robust(cameras, obs, w)
                out_conf[t, j] = float(w[mask].mean()) if mask.any() else 0.0
            else:
                X = triangulate_point(cameras, obs, w)
                out_conf[t, j] = float(w.mean())
            out[t, j] = X
    return out, out_conf
