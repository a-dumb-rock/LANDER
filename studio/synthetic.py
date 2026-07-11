"""Generate a parametric 3D drop-vertical-jump landing (ground-truth skeleton).

This is the honest core of Studio's validation. We build a moving 3D skeleton with
known, physically-plausible knee flexion and valgus, in world coordinates. Then:

  * the **self-test** projects it into several virtual cameras, triangulates it back,
    and checks the recovered angles match the ground truth (proving the geometry);
  * the **demo** analyses it directly so the dashboard has a realistic capture to
    render without needing real video.

Segment lengths are fixed anthropometrics (metres). The valgus is injected by
rotating each knee about its own hip->ankle axis, which *exactly* preserves segment
lengths and knee-flexion angle while swinging the knee out of the sagittal plane —
so flexion and valgus are controlled independently and realistically.

World convention: +Z up, athlete faces +Y (anterior), +X = athlete's right.
"""

from __future__ import annotations

import numpy as np

from landr import config
from landr.types import PoseSequence

# Anthropometrics (metres).
_HIP_HALF = 0.10
_SHOULDER_HALF = 0.18
_THIGH = 0.42
_SHANK = 0.42
_TORSO = 0.50
_NECK = 0.24
_FOOT = 0.18


def _rot_x(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], float)


def _rodrigues(axis: np.ndarray, angle: float) -> np.ndarray:
    """Rotation matrix about a unit ``axis`` by ``angle`` radians (Rodrigues)."""
    u = axis / (np.linalg.norm(axis) + 1e-12)
    K = np.array([[0, -u[2], u[1]], [u[2], 0, -u[0]], [-u[1], u[0], 0]], float)
    return np.eye(3) + np.sin(angle) * K + (1 - np.cos(angle)) * (K @ K)


def _smootherstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * x * (x * (x * 6 - 15) + 10)


def _profile(T: int) -> tuple[np.ndarray, np.ndarray]:
    """Return (hip_height, knee_flexion_deg) trajectories over T frames.

    Models a real drop-vertical-jump: a stand, a quick fall to impact (legs reaching,
    so flexion stays low), then absorption to a deep low point, then a partial
    recovery. Flexion deliberately LAGS the fall so knee flexion at initial contact
    is a realistic ~30 deg (not already-deep), and the hip has a crisp minimum for
    the landing-event detector.
    """
    p = np.linspace(0.0, 1.0, T)
    # Hip: quick fall (velocity peaks early -> initial contact is detected early),
    # then absorb to the low point, then recover.
    fall = _smootherstep((p - 0.20) / 0.22)
    recover = _smootherstep((p - 0.50) / 0.50)
    h_stand, h_low, h_settle = 1.00, 0.58, 0.74
    hip_h = h_stand - (h_stand - h_low) * fall + (h_settle - h_low) * recover
    hip_h = np.minimum(hip_h, h_stand)

    # Flexion lags the fall slightly: the knees are partly extended reaching for the
    # ground, then absorb through the low point. Tuned so flexion at the detected
    # initial contact is a realistic ~30 deg.
    absorb = _smootherstep((p - 0.235) / 0.24)
    relax = _smootherstep((p - 0.56) / 0.44)
    f_stand, f_low, f_settle = 12.0, 95.0, 55.0
    flex = f_stand + (f_low - f_stand) * absorb - (f_low - f_settle) * relax
    return hip_h, flex


def _leg(
    hip: np.ndarray, side: str, flex_deg: float, valgus_cm: float
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Build (knee, ankle, foot) for one leg with prescribed flexion + valgus.

    ``valgus_cm`` is the medial knee displacement in centimetres. Injecting valgus as
    a medio-lateral (frontal-plane) translation keeps the resulting frontal-plane
    projection angle independent of knee-flexion depth — a physically faithful "knee
    caves toward the midline" rather than an artefact of deep flexion.
    """
    theta_t = np.radians(8.0)  # baseline forward thigh tilt
    f = np.radians(flex_deg)

    down = np.array([0.0, 0.0, -1.0])
    # Distribute flexion between thigh (tips forward) and shank (tips back) so the
    # shank stays near-vertical at depth — a realistic squat, not a horizontal shin.
    # Interior angle hip-knee-ankle stays 180-f, so flexion is exactly as prescribed.
    thigh_dir = _rot_x(theta_t + f / 2.0) @ down
    shank_dir = _rot_x(theta_t - f / 2.0) @ down
    knee = hip + _THIGH * thigh_dir
    ankle = knee + _SHANK * shank_dir
    foot = ankle + np.array([0.0, _FOOT, -0.03])

    # Medial collapse: shift the knee toward the midline (left: +X, right: -X).
    medial_sign = +1.0 if side == "left" else -1.0
    knee = knee + np.array([medial_sign * valgus_cm * 0.01, 0.0, 0.0])
    return knee, ankle, foot


def make_landing_capture(
    n_frames: int = 90,
    fps: float = 60.0,
    valgus_gain: float = 12.0,
    asymmetry: float = 0.0,
    trunk_lean_deg: float = 22.0,
    facing_deg: float = 0.0,
    depth_scale: float = 1.0,
    seed: int | None = None,
) -> PoseSequence:
    """Create a world-frame :class:`PoseSequence` of a drop-vertical-jump landing.

    valgus_gain : peak medial-collapse angle (deg) injected at the deepest point.
    asymmetry   : fraction by which the two legs differ in BOTH valgus and peak
                  flexion (0 = symmetric); it maps ~directly to the engine's
                  asymmetry index.
    depth_scale : scales absorption depth (<1 = stiffer, shallower landing -> lower
                  knee-flexion displacement and a stiffer initial contact).
    facing_deg  : yaw of the athlete about vertical, so the rig sees them off-axis
                  (this is exactly what breaks single-camera 2D and what 3D fixes).
    """
    rng = np.random.default_rng(seed)
    hip_h, flex = _profile(n_frames)
    flex = flex * depth_scale
    # Valgus grows with landing depth (normalised flexion).
    depth = (flex - flex.min()) / (flex.max() - flex.min() + 1e-9)

    yaw = np.radians(facing_deg)
    Rz = np.array(
        [[np.cos(yaw), -np.sin(yaw), 0], [np.sin(yaw), np.cos(yaw), 0], [0, 0, 1]], float
    )

    frames = np.zeros((n_frames, config.NUM_LANDMARKS, 3))
    for i in range(n_frames):
        hip_mid = np.array([0.0, 0.0, hip_h[i]])
        l_hip = hip_mid + np.array([-_HIP_HALF, 0.0, 0.0])
        r_hip = hip_mid + np.array([+_HIP_HALF, 0.0, 0.0])

        trunk_dir = _rot_x(np.radians(trunk_lean_deg)) @ np.array([0.0, 0.0, 1.0])
        sh_mid = hip_mid + _TORSO * trunk_dir
        l_sh = sh_mid + np.array([-_SHOULDER_HALF, 0.0, 0.0])
        r_sh = sh_mid + np.array([+_SHOULDER_HALF, 0.0, 0.0])
        nose = sh_mid + _NECK * trunk_dir

        v_left = valgus_gain * depth[i] * (1.0 + asymmetry)
        v_right = valgus_gain * depth[i] * (1.0 - asymmetry)
        # Per-leg flexion asymmetry maps ~directly to the engine's asymmetry index
        # (|L-R| / mean = asymmetry).
        f_left = flex[i] * (1.0 + 0.5 * asymmetry)
        f_right = flex[i] * (1.0 - 0.5 * asymmetry)
        l_knee, l_ank, l_foot = _leg(l_hip, "left", f_left, v_left)
        r_knee, r_ank, r_foot = _leg(r_hip, "right", f_right, v_right)

        pts = np.zeros((config.NUM_LANDMARKS, 3))
        pts[config.NOSE] = nose
        pts[config.LEFT_SHOULDER] = l_sh
        pts[config.RIGHT_SHOULDER] = r_sh
        pts[config.LEFT_HIP] = l_hip
        pts[config.RIGHT_HIP] = r_hip
        pts[config.LEFT_KNEE] = l_knee
        pts[config.RIGHT_KNEE] = r_knee
        pts[config.LEFT_ANKLE] = l_ank
        pts[config.RIGHT_ANKLE] = r_ank
        pts[config.LEFT_FOOT_INDEX] = l_foot
        pts[config.RIGHT_FOOT_INDEX] = r_foot

        # Yaw the whole athlete about vertical through the hip centre.
        pts = (pts - hip_mid) @ Rz.T + hip_mid
        frames[i] = pts

    vis = np.zeros((n_frames, config.NUM_LANDMARKS))
    used = [
        config.NOSE, config.LEFT_SHOULDER, config.RIGHT_SHOULDER,
        config.LEFT_HIP, config.RIGHT_HIP, config.LEFT_KNEE, config.RIGHT_KNEE,
        config.LEFT_ANKLE, config.RIGHT_ANKLE, config.LEFT_FOOT_INDEX,
        config.RIGHT_FOOT_INDEX,
    ]
    vis[:, used] = 1.0

    return PoseSequence(
        landmarks=frames,
        fps=fps,
        visibility=vis,
        meta={"source": "studio.synthetic", "frame": "world", "facing_deg": facing_deg},
    )


def project_to_views(
    seq: PoseSequence, rig, pixel_noise: float = 0.0, seed: int | None = None
) -> tuple[np.ndarray, np.ndarray]:
    """Project a world-frame sequence into every camera of a rig.

    Returns ``(keypoints_2d, confidences)`` shaped (M, T, J, 2) and (M, T, J), ready
    for :func:`studio.triangulation.triangulate_sequence`. Gaussian ``pixel_noise``
    (std, in px) simulates detector jitter; visibility carries into confidence.
    """
    rng = np.random.default_rng(seed)
    M = len(rig.cameras)
    T, J = seq.landmarks.shape[:2]
    kp = np.zeros((M, T, J, 2))
    conf = np.zeros((M, T, J))
    vis = seq.visibility
    for ci, cam in enumerate(rig.cameras):
        proj = cam.project(seq.landmarks.reshape(-1, 3)).reshape(T, J, 2)
        if pixel_noise > 0:
            proj = proj + rng.normal(0.0, pixel_noise, proj.shape)
        kp[ci] = proj
        # Confidence = visibility, dropped for joints behind the camera.
        depth = cam.depth(seq.landmarks.reshape(-1, 3)).reshape(T, J)
        conf[ci] = np.where(depth > 0, vis, 0.0)
    return kp, conf
