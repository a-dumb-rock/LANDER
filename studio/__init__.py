"""LANDR Studio — the multi-camera, lab-grade motion-capture product.

Where **LANDR Mobile** is a single-phone, longitudinal *personal* monitor (2D per
view, valgus accurate to ~9 deg, best used for per-athlete trend detection),
**LANDR Studio** is a fixed multi-camera rig for clinics, teams and return-to-sport
clearance. It reconstructs *true 3D* joint centres by triangulating 2D keypoints
from several calibrated cameras — the same geometry that gives OpenCap its ~1 deg
lab accuracy.

Why 3D is the accuracy win (not "training a bigger model"):
    A single camera can only ever *project* a 3D motion onto its image plane, so an
    out-of-plane knee cave leaks into (or out of) the measured valgus depending on
    how the athlete is oriented to the lens. Multi-view triangulation removes that
    ambiguity by construction — given good calibration and 2D keypoints, the 3D
    joint is recovered by geometry, and the frontal-plane angle is measured in the
    athlete's *anatomical* frame rather than a camera's image plane.

Design principle — reuse the clinical engine:
    Studio does NOT reinvent the biomechanics. It produces an accurate 3D
    :class:`~landr.types.PoseSequence`, rotates it into the athlete's anatomical
    frame, and feeds it through the *exact same* ``compute_metrics`` /
    ``score_less`` / ``assess_risk`` used by LANDR Mobile. Same clinical
    definitions, better geometry underneath.

What is validated vs pending:
    * PROVEN (``python -m studio.selftest``): the whole geometric chain —
      projection -> triangulation -> anatomical frame -> angle recovery — is exact
      to sub-degree on synthetic ground truth, and degrades gracefully under pixel
      noise. This proves the *pipeline* is correct.
    * PENDING: real-world accuracy vs marker mocap, which needs real synchronised
      multi-camera capture (or the still-blocked OpenCap LabValidation set). Studio
      is written so that swapping synthetic keypoints for real RTMPose detections is
      a one-line change.
"""

from __future__ import annotations

from .calibration import Camera, CameraRig
from .pipeline import CaptureView, analyze_capture
from .triangulation import triangulate_point, triangulate_sequence

__all__ = [
    "Camera",
    "CameraRig",
    "CaptureView",
    "analyze_capture",
    "triangulate_point",
    "triangulate_sequence",
]
