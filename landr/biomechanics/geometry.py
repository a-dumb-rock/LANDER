"""Low-level geometry helpers: vector angles and frontal-plane projection."""

from __future__ import annotations

import numpy as np

_EPS = 1e-8


def angle_3d(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Interior angle at vertex ``b`` formed by points a-b-c, in degrees [0,180]."""
    a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
    ba = a - b
    bc = c - b
    denom = np.linalg.norm(ba) * np.linalg.norm(bc)
    if denom < _EPS:  # degenerate (coincident points)
        return 0.0
    cosang = np.clip(np.dot(ba, bc) / denom, -1.0, 1.0)
    return float(np.degrees(np.arccos(cosang)))


def flexion_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Joint flexion in degrees where 0 = fully extended (straight)."""
    return 180.0 - angle_3d(a, b, c)


def frontal_plane_projection_angle(
    hip: np.ndarray, knee: np.ndarray, ankle: np.ndarray
) -> float:
    """Frontal-plane projection angle (FPPA) of the knee, in degrees."""
    interior = angle_3d(
        np.array([hip[0], hip[1], 0.0]),
        np.array([knee[0], knee[1], 0.0]),
        np.array([ankle[0], ankle[1], 0.0]),
    )
    return 180.0 - interior


def signed_knee_valgus(
    hip: np.ndarray, knee: np.ndarray, ankle: np.ndarray, side: str
) -> float:
    """Signed frontal-plane knee valgus angle in degrees.

    Positive = valgus (knee collapses medially) — the risky direction.
    Negative = varus (knee bows outward).
    """
    fppa = frontal_plane_projection_angle(hip, knee, ankle)
    hy, ay = hip[1], ankle[1]
    if abs(ay - hy) < _EPS:
        line_x = (hip[0] + ankle[0]) / 2.0
    else:
        t = (knee[1] - hy) / (ay - hy)
        line_x = hip[0] + t * (ankle[0] - hip[0])
    offset = knee[0] - line_x
    medial_sign = +1.0 if side == "left" else -1.0
    medial_offset = offset * medial_sign
    return float(np.sign(medial_offset) * abs(fppa)) if abs(fppa) > _EPS else 0.0


def trunk_flexion_from_vertical(
    shoulder_mid: np.ndarray, hip_mid: np.ndarray
) -> float:
    """Trunk flexion in degrees away from vertical (0 = perfectly upright)."""
    trunk = np.asarray(shoulder_mid, float) - np.asarray(hip_mid, float)
    vertical = np.array([0.0, 1.0, 0.0])
    denom = np.linalg.norm(trunk)
    if denom < _EPS:
        return 0.0
    cosang = np.clip(np.dot(trunk, vertical) / denom, -1.0, 1.0)
    return float(np.degrees(np.arccos(cosang)))


def smooth(signal: np.ndarray, window: int = 5) -> np.ndarray:
    """Simple odd-window moving average; robust to short signals."""
    signal = np.asarray(signal, float)
    if window < 2 or signal.size < window:
        return signal
    if window % 2 == 0:
        window += 1
    pad = window // 2
    padded = np.pad(signal, pad, mode="edge")
    kernel = np.ones(window) / window
    return np.convolve(padded, kernel, mode="valid")
