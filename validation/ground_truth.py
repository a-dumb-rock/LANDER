"""Compute ground-truth angle series from the OpenCap lab data.

Two independent ground-truth sources, matched to what each metric can honestly
validate:

  * **Knee flexion** — take it straight from the OpenSim inverse-kinematics
    ``.mot`` (``knee_angle_r/l``). This is the field's gold standard for sagittal
    knee angle; sign/zero differences are reconciled globally by ``align.fit_convention``.

  * **Knee valgus (FPPA)** — there is no standard OpenSim frontal-plane knee DOF,
    so we derive a marker-based frontal-plane projection angle from the mocap
    hip/knee/ankle joint centres, using **LANDR's own** ``signed_knee_valgus``.
    Identical geometry on both sides means we measure keypoint error, not a
    method mismatch.

Joint-centre trajectories passed in here are already expressed in LANDR's
convention (x = medio-lateral, y = up, z = anterior-posterior); the axis mapping
from the lab frame lives in ``adapter.py`` because it is dataset-specific.
"""

from __future__ import annotations

import numpy as np

# Reuse LANDR's exact geometry so GT and prediction are computed the same way.
from landr.biomechanics.geometry import flexion_angle, signed_knee_valgus

from .opensim_io import MotData


_KNEE_ANGLE_COL  = {"left": "knee_angle_l",    "right": "knee_angle_r"}
_HIP_ADDUCT_COL  = {"left": "hip_adduction_l", "right": "hip_adduction_r"}


def flexion_from_mot(mot: MotData, side: str) -> tuple[np.ndarray, np.ndarray]:
    """Ground-truth knee-flexion series (time_s, angle_deg) from OpenSim IK.

    Returns the raw joint angle in degrees (converted from radians if needed).
    Sign/zero convention is left to the global ``Convention`` fit, not fudged here.
    """
    col = _KNEE_ANGLE_COL[side]
    if not mot.has(col):
        raise KeyError(f"{col!r} not found in .mot columns: {mot.columns}")
    ang = mot.column(col).astype(float)
    if not mot.in_degrees:
        ang = np.degrees(ang)
    return mot.time().astype(float), ang


def valgus_from_centers(
    hip: np.ndarray, knee: np.ndarray, ankle: np.ndarray, side: str
) -> np.ndarray:
    """Ground-truth signed valgus series from mocap joint centres (LANDR geometry).

    hip/knee/ankle : (T, 3) arrays in LANDR convention.
    """
    hip, knee, ankle = np.asarray(hip, float), np.asarray(knee, float), np.asarray(ankle, float)
    return np.array([
        signed_knee_valgus(hip[f], knee[f], ankle[f], side) for f in range(len(hip))
    ])


def valgus_from_ik(mot: MotData, side: str) -> tuple[np.ndarray, np.ndarray]:
    """Ground-truth knee valgus from OpenSim IK hip-adduction angle.

    In OpenSim, hip_adduction_r is negative when the knee is adducted (valgus).
    We negate so positive = valgus, matching LANDR's FPPA sign convention.
    The global Convention fit handles any remaining scale/offset differences
    between FPPA and the 3D musculoskeletal angle.
    """
    col = _HIP_ADDUCT_COL[side]
    if not mot.has(col):
        raise KeyError(f"{col!r} not found in .mot columns: {mot.columns}")
    ang = mot.column(col).astype(float)
    if not mot.in_degrees:
        ang = np.degrees(ang)
    return mot.time().astype(float), -ang   # negate: adduction+ -> valgus+


def valgus_from_projected(
    hip_mm: np.ndarray,
    knee_mm: np.ndarray,
    ankle_mm: np.ndarray,
    side: str,
    calib: dict,
) -> np.ndarray:
    """Ground-truth valgus by projecting mocap markers through the camera matrix.

    This is the correct apples-to-apples comparison: both LANDR and GT compute
    FPPA from the same 2D pixel-plane projection of the frontal camera.

    hip_mm / knee_mm / ankle_mm : (T, 3) in original lab frame mm (NOT remapped).
    calib : dict from adapter.load_camera_calib() with K, R, t, dist.
    """
    import cv2 as _cv2

    K    = calib["K"]
    R    = calib["R"]
    t    = calib["t"].reshape(3, 1)
    dist = calib["dist"]
    rvec, _ = _cv2.Rodrigues(R)

    def _project(pts_mm: np.ndarray) -> np.ndarray:
        # pts_mm: (T, 3) -> (T, 2) pixel coordinates
        pts = pts_mm.astype(float).reshape(-1, 1, 3)
        px, _ = _cv2.projectPoints(pts, rvec, t, K, dist)
        return px.reshape(-1, 2)

    hip_px   = _project(hip_mm)
    knee_px  = _project(knee_mm)
    ankle_px = _project(ankle_mm)

    return np.array([
        signed_knee_valgus(hip_px[f], knee_px[f], ankle_px[f], side)
        for f in range(len(hip_px))
    ])


def flexion_from_projected(
    hip_mm: np.ndarray,
    knee_mm: np.ndarray,
    ankle_mm: np.ndarray,
    calib: dict,
) -> np.ndarray:
    """Ground-truth flexion by projecting mocap markers through the side camera.

    Projects 3D markers to 2D pixel coords, then computes the same 2D flexion
    angle LANDR uses — true apples-to-apples for sagittal-plane flexion.
    """
    import cv2 as _cv2

    K    = calib["K"]
    R    = calib["R"]
    t    = calib["t"].reshape(3, 1)
    dist = calib["dist"]
    rvec, _ = _cv2.Rodrigues(R)

    def _project(pts_mm: np.ndarray) -> np.ndarray:
        pts = pts_mm.astype(float).reshape(-1, 1, 3)
        px, _ = _cv2.projectPoints(pts, rvec, t, K, dist)
        return px.reshape(-1, 2)

    hip_px   = _project(hip_mm)
    knee_px  = _project(knee_mm)
    ankle_px = _project(ankle_mm)

    return np.array([
        flexion_angle(hip_px[f], knee_px[f], ankle_px[f])
        for f in range(len(hip_px))
    ])


def flexion_from_centers(
    hip: np.ndarray, knee: np.ndarray, ankle: np.ndarray
) -> np.ndarray:
    """Ground-truth flexion series from mocap joint centres (rotation-invariant).

    A cross-check on ``flexion_from_mot``: because ``flexion_angle`` is a 3D
    interior angle it is independent of coordinate frame, so this needs no axis map.
    """
    hip, knee, ankle = np.asarray(hip, float), np.asarray(knee, float), np.asarray(ankle, float)
    return np.array([
        flexion_angle(hip[f], knee[f], ankle[f]) for f in range(len(hip))
    ])
