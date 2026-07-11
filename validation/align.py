"""Time-align two angle series and score error — honestly.

The whole point of the validation is a trustworthy number, so the alignment here
is deliberately *minimal*. We allow exactly two global corrections, both of which
are legitimate (they reconcile measurement conventions, they do not fit noise):

  1. A single **time lag** (one integer/scalar shift for the whole clip), found by
     cross-correlation, because the phone video and the mocap clock start at
     different instants.
  2. A single **convention map** (one global sign, and one global offset) because
     "knee flexion = 0 at full extension" in LANDR may differ from the OpenSim
     joint's zero/sign. One number for the whole dataset, fit on the TUNE split
     only.

What we explicitly do NOT do (these would be cheating / overfitting):
  * per-frame time warping (DTW) — would erase real dynamic error,
  * per-clip offsets — would hide systematic bias,
  * any parameter fit on the test split.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


def resample_to(t_src: np.ndarray, y_src: np.ndarray, t_ref: np.ndarray) -> np.ndarray:
    """Linearly resample ``y_src`` (sampled at ``t_src``) onto ``t_ref``."""
    t_src = np.asarray(t_src, float)
    y_src = np.asarray(y_src, float)
    order = np.argsort(t_src)
    return np.interp(t_ref, t_src[order], y_src[order])


def best_lag(pred: np.ndarray, gt: np.ndarray, max_lag: int) -> int:
    """Integer sample shift of ``pred`` that best matches ``gt`` (cross-correlation).

    Positive lag means ``pred`` is delayed relative to ``gt``. Both inputs must be
    on the same uniform time base and equal length.
    """
    pred = np.asarray(pred, float)
    gt = np.asarray(gt, float)
    n = min(len(pred), len(gt))
    pred, gt = pred[:n], gt[:n]
    p = pred - pred.mean()
    g = gt - gt.mean()
    max_lag = int(min(max_lag, n - 1))
    best, best_corr = 0, -np.inf
    for lag in range(-max_lag, max_lag + 1):
        if lag < 0:
            a, b = p[-lag:], g[: n + lag]
        elif lag > 0:
            a, b = p[: n - lag], g[lag:]
        else:
            a, b = p, g
        if len(a) < 3:
            continue
        denom = np.linalg.norm(a) * np.linalg.norm(b)
        corr = float(np.dot(a, b) / denom) if denom > 1e-9 else -np.inf
        if corr > best_corr:
            best_corr, best = corr, lag
    return best


def apply_lag(pred: np.ndarray, gt: np.ndarray, lag: int) -> tuple[np.ndarray, np.ndarray]:
    """Trim both series to their overlapping region after shifting ``pred`` by ``lag``."""
    n = min(len(pred), len(gt))
    pred, gt = pred[:n], gt[:n]
    if lag < 0:
        return pred[-lag:], gt[: n + lag]
    if lag > 0:
        return pred[: n - lag], gt[lag:]
    return pred, gt


@dataclass
class Convention:
    """A global mapping from LANDR angles to the GT convention.

    apply(y) = sign * scale * y + offset. ``scale`` defaults to 1.0 so the
    sign+offset convention from ``fit_convention`` behaves as a pure flip+shift;
    the gain term exists only so diagnostics can express a fitted linear gain.
    """

    sign: float = 1.0
    offset: float = 0.0
    scale: float = 1.0

    def apply(self, y: np.ndarray) -> np.ndarray:
        return self.sign * self.scale * np.asarray(y, float) + self.offset


def fit_convention(pred: np.ndarray, gt: np.ndarray) -> Convention:
    """Fit ONE global sign and ONE global offset (least squares on the tune split).

    We only allow sign in {+1, -1} (a convention flip, not a scale fit) and a
    single additive offset. This corrects definition differences, not error.
    """
    pred = np.asarray(pred, float)
    gt = np.asarray(gt, float)
    best = Convention()
    best_err = np.inf
    for sign in (1.0, -1.0):
        offset = float(np.mean(gt - sign * pred))
        err = float(np.sqrt(np.mean((sign * pred + offset - gt) ** 2)))
        if err < best_err:
            best_err, best = err, Convention(sign=sign, offset=offset)
    return best


def rmse(pred: np.ndarray, gt: np.ndarray) -> float:
    """Root-mean-square error in the units of the inputs (degrees)."""
    pred = np.asarray(pred, float)
    gt = np.asarray(gt, float)
    n = min(len(pred), len(gt))
    return float(np.sqrt(np.mean((pred[:n] - gt[:n]) ** 2)))


@dataclass
class AlignedPair:
    pred: np.ndarray
    gt: np.ndarray
    lag: int
    fps: float


def align_series(
    t_pred: np.ndarray,
    y_pred: np.ndarray,
    t_gt: np.ndarray,
    y_gt: np.ndarray,
    convention: Convention | None = None,
    ref_fps: float = 60.0,
    max_lag_s: float = 1.0,
) -> AlignedPair:
    """Put predicted and GT angle series on a common time base and lag-align them.

    convention : applied to ``y_pred`` BEFORE alignment. Pass the one fit on the
                 tune split; pass None to skip (identity).
    ref_fps    : common resampling rate for both series.
    """
    if convention is not None:
        y_pred = convention.apply(y_pred)

    t0 = max(float(t_pred[0]), float(t_gt[0]))
    t1 = min(float(t_pred[-1]), float(t_gt[-1]))
    if t1 <= t0:
        raise ValueError("predicted and GT time ranges do not overlap")
    t_ref = np.arange(t0, t1, 1.0 / ref_fps)

    p = resample_to(t_pred, y_pred, t_ref)
    g = resample_to(t_gt, y_gt, t_ref)
    lag = best_lag(p, g, max_lag=int(max_lag_s * ref_fps))
    p2, g2 = apply_lag(p, g, lag)
    return AlignedPair(pred=p2, gt=g2, lag=lag, fps=ref_fps)
