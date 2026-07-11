"""End-to-end LANDR Studio pipeline: multi-view capture -> clinical analysis.

Flow:
    per-view 2D keypoints  (RTMPose, or precomputed)
        -> triangulate to true 3D world joints            (triangulation.py)
        -> rotate into the athlete's anatomical frame      (anatomical.py)
        -> landing events + metrics + LESS + risk          (the shared landr engine)
        -> AnalysisResult (+ 3D provenance for the dashboard)

The clinical stage is the *identical* engine LANDR Mobile uses, so a Studio report
and a Mobile report speak the same language — Studio just feeds it lab-grade 3D.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Sequence

import numpy as np

from landr.biomechanics import compute_metrics, detect_landing_events
from landr.scoring import assess_risk, score_less
from landr.types import AnalysisResult, PoseSequence

from .anatomical import to_anatomical
from .calibration import Camera, CameraRig
from .detector import RTMPoseDetector, keypoints_from_arrays
from .triangulation import triangulate_sequence


@dataclass
class CaptureView:
    """One camera's contribution to a capture.

    Provide EITHER ``video`` (a path, detected with RTMPose) OR precomputed
    ``keypoints`` (T, J, 2) with optional ``confidences`` (T, J). ``camera`` is the
    calibrated :class:`Camera` for this view.
    """

    camera: Camera
    video: str | None = None
    keypoints: np.ndarray | None = None
    confidences: np.ndarray | None = None


def _collect_view(view: CaptureView, detector: RTMPoseDetector) -> tuple[np.ndarray, np.ndarray, float | None]:
    if view.keypoints is not None:
        kp, conf = keypoints_from_arrays(view.keypoints, view.confidences)
        return kp, conf, None
    if view.video is not None:
        return detector.run(view.video)
    raise ValueError("CaptureView needs either 'video' or 'keypoints'")


def reconstruct_3d(
    views: Sequence[CaptureView],
    up: np.ndarray,
    robust: bool = True,
    detector: RTMPoseDetector | None = None,
    fps: float = 60.0,
) -> tuple[PoseSequence, PoseSequence, np.ndarray]:
    """Triangulate views into a 3D sequence and return (world, anatomical, conf3d).

    All views must be frame-synchronised and share the joint indexing. ``up`` is the
    rig's world up-vector.
    """
    detector = detector or RTMPoseDetector()
    cameras: list[Camera] = []
    kps: list[np.ndarray] = []
    confs: list[np.ndarray] = []
    det_fps: float | None = None
    for v in views:
        kp, conf, f = _collect_view(v, detector)
        cameras.append(v.camera)
        kps.append(kp)
        confs.append(conf)
        if f is not None:
            det_fps = f

    T = min(k.shape[0] for k in kps)
    J = kps[0].shape[1]
    kp_stack = np.stack([k[:T] for k in kps])  # (M,T,J,2)
    conf_stack = np.stack([c[:T] for c in confs])  # (M,T,J)

    pts3d, conf3d = triangulate_sequence(cameras, kp_stack, conf_stack, robust=robust)
    world = PoseSequence(
        landmarks=pts3d,
        fps=det_fps or fps,
        visibility=conf3d,
        meta={"source": "studio", "frame": "world", "n_views": len(views)},
    )
    anatomical = to_anatomical(world, up)
    return world, anatomical, conf3d


def analyze_capture(
    views: Sequence[CaptureView],
    rig: CameraRig,
    athlete: dict[str, Any] | None = None,
    robust: bool = True,
    fps: float = 60.0,
) -> AnalysisResult:
    """Run the full Studio pipeline on a multi-view capture.

    Returns an :class:`~landr.types.AnalysisResult` whose ``meta`` carries the 3D
    provenance (reconstruction confidence, number of views, the anatomical-frame 3D
    trajectory) so the dashboard can render the reconstruction.
    """
    if len(views) != len(rig.cameras):
        # Allow the caller to pass cameras only via the rig; bind them by order.
        for v, cam in zip(views, rig.cameras):
            if v.camera is None:  # type: ignore[truthy-bool]
                v.camera = cam

    world, anatomical, conf3d = reconstruct_3d(
        views, up=rig.up, robust=robust, fps=fps
    )

    events = detect_landing_events(anatomical)
    metrics = compute_metrics(anatomical, events)
    less = score_less(metrics)
    risk = assess_risk(less, metrics)

    # Mean over joints that were actually reconstructed (skip the unused MediaPipe
    # slots, whose confidence is 0 and would otherwise deflate the figure).
    nz = conf3d[conf3d > 0]
    mean_conf = float(nz.mean()) if nz.size else 0.0
    result = AnalysisResult(
        metrics=metrics,
        events=events,
        less=less,
        risk=risk,
        meta={
            "product": "studio",
            "mode": "multiview_3d",
            "n_views": len(views),
            "reconstruction_confidence": round(mean_conf, 3),
            "athlete": athlete or {},
            "skeleton_3d": _skeleton_payload(anatomical),
        },
    )
    return result


def _skeleton_payload(seq: PoseSequence) -> dict[str, Any]:
    """Compact 3D skeleton (anatomical frame) for the dashboard's viewer."""
    from landr import config

    joints = {
        "nose": config.NOSE,
        "l_shoulder": config.LEFT_SHOULDER,
        "r_shoulder": config.RIGHT_SHOULDER,
        "l_hip": config.LEFT_HIP,
        "r_hip": config.RIGHT_HIP,
        "l_knee": config.LEFT_KNEE,
        "r_knee": config.RIGHT_KNEE,
        "l_ankle": config.LEFT_ANKLE,
        "r_ankle": config.RIGHT_ANKLE,
        "l_foot": config.LEFT_FOOT_INDEX,
        "r_foot": config.RIGHT_FOOT_INDEX,
    }
    out = {name: np.round(seq.landmarks[:, idx, :], 4).tolist() for name, idx in joints.items()}
    out["fps"] = seq.fps
    return out
