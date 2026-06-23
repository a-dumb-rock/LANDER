"""MediaPipe-based pose estimation with a graceful fallback.

Supports BOTH MediaPipe APIs so it works across versions:
  * the legacy ``mp.solutions.pose`` API, and
  * the current **Tasks API** (``mediapipe.tasks ... PoseLandmarker``), which is
    what recent MediaPipe builds (e.g. on Colab / Python 3.12) expose. The Tasks
    path auto-downloads a small pose model on first use.

If ``mediapipe`` / ``opencv-python`` aren't installed, importing this module still
works — only calling :func:`estimate_from_video` raises a clear error. Swapping in
a higher-accuracy backend (RTMPose/MMPose, OpenCap) means implementing one method
that returns a :class:`~landr.types.PoseSequence`.
"""

from __future__ import annotations

import os
import tempfile
import urllib.request

import numpy as np

from ..config import NUM_LANDMARKS
from ..types import PoseSequence

try:  # optional heavy deps
    import cv2  # type: ignore
    import mediapipe as mp  # type: ignore

    MEDIAPIPE_AVAILABLE = True
except Exception:  # pragma: no cover
    MEDIAPIPE_AVAILABLE = False

# Pose models for the Tasks API, by accuracy/speed tier.
_TASK_MODEL_URLS = {
    "lite": "pose_landmarker_lite/float16/1/pose_landmarker_lite.task",
    "full": "pose_landmarker_full/float16/1/pose_landmarker_full.task",
    "heavy": "pose_landmarker_heavy/float16/1/pose_landmarker_heavy.task",
}
_TASK_MODEL_BASE = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
# Map model size -> legacy mp.solutions complexity (0 lite, 1 full, 2 heavy).
_LEGACY_COMPLEXITY = {"lite": 0, "full": 1, "heavy": 2}


class PoseEstimator:
    """Wraps MediaPipe Pose to produce a :class:`PoseSequence` from a video.

    Parameters
    ----------
    model_size : {'lite', 'full', 'heavy'}
        Accuracy/speed tier. 'full' is a good default; 'heavy' is most accurate
        but slowest (use for final runs, not quick tests).
    """

    def __init__(
        self,
        model_size: str = "full",
        min_detection_confidence: float = 0.5,
        min_tracking_confidence: float = 0.5,
    ) -> None:
        if not MEDIAPIPE_AVAILABLE:
            raise ImportError(
                "PoseEstimator requires `mediapipe` and `opencv-python`.\n"
                "Install them with:  pip install mediapipe opencv-python\n"
                "Or run on synthetic data:  python -m landr.cli demo"
            )
        if model_size not in _TASK_MODEL_URLS:
            raise ValueError(f"model_size must be one of {list(_TASK_MODEL_URLS)}")
        self.model_size = model_size
        self.model_complexity = _LEGACY_COMPLEXITY[model_size]
        self.min_detection_confidence = min_detection_confidence
        self.min_tracking_confidence = min_tracking_confidence

    # ------------------------------------------------------------------ #
    def estimate(self, video_path: str) -> PoseSequence:
        """Dispatch to whichever MediaPipe API is available."""
        if hasattr(mp, "solutions") and hasattr(mp.solutions, "pose"):
            return self._estimate_legacy(video_path)
        return self._estimate_tasks(video_path)

    # ------------------------------------------------------------------ #
    def _open(self, video_path: str):
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise FileNotFoundError(f"Could not open video: {video_path}")
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        return cap, float(fps)

    def _finish(self, frames, vis, fps, video_path, api):
        if not frames:
            raise ValueError(
                f"No pose detected in {video_path}. Is a full body visible and "
                f"well-lit throughout the clip?"
            )
        return PoseSequence(
            landmarks=np.stack(frames),
            fps=fps,
            visibility=np.stack(vis),
            meta={"source": video_path, "estimator": f"mediapipe:{api}", "fps": fps},
        )

    # ------------------------------------------------------------------ #
    def _estimate_legacy(self, video_path: str) -> PoseSequence:
        cap, fps = self._open(video_path)
        frames: list[np.ndarray] = []
        vis: list[np.ndarray] = []
        mp_pose = mp.solutions.pose
        with mp_pose.Pose(
            model_complexity=self.model_complexity,
            min_detection_confidence=self.min_detection_confidence,
            min_tracking_confidence=self.min_tracking_confidence,
            smooth_landmarks=True,
        ) as pose:
            while True:
                ok, frame_bgr = cap.read()
                if not ok:
                    break
                frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
                result = pose.process(frame_rgb)
                pts = np.zeros((NUM_LANDMARKS, 3), dtype=float)
                vrow = np.zeros(NUM_LANDMARKS, dtype=float)
                lms = getattr(result, "pose_world_landmarks", None) or getattr(
                    result, "pose_landmarks", None
                )
                if lms is not None:
                    for i, lm in enumerate(lms.landmark):
                        pts[i] = (lm.x, -lm.y, getattr(lm, "z", 0.0))
                        vrow[i] = getattr(lm, "visibility", 1.0)
                    frames.append(pts)
                    vis.append(vrow)
        cap.release()
        return self._finish(frames, vis, fps, video_path, "solutions")

    # ------------------------------------------------------------------ #
    def _ensure_task_model(self) -> str:
        fname = f"pose_landmarker_{self.model_size}.task"
        cache = os.path.join(tempfile.gettempdir(), fname)
        if not os.path.exists(cache):
            url = _TASK_MODEL_BASE + _TASK_MODEL_URLS[self.model_size]
            urllib.request.urlretrieve(url, cache)
        return cache

    def _estimate_tasks(self, video_path: str) -> PoseSequence:
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision as mp_vision

        model_path = self._ensure_task_model()
        options = mp_vision.PoseLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=model_path),
            running_mode=mp_vision.RunningMode.IMAGE,
            num_poses=1,
        )
        cap, fps = self._open(video_path)
        frames: list[np.ndarray] = []
        vis: list[np.ndarray] = []
        with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
            while True:
                ok, frame_bgr = cap.read()
                if not ok:
                    break
                frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
                mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
                result = landmarker.detect(mp_image)
                world = getattr(result, "pose_world_landmarks", None)
                norm = getattr(result, "pose_landmarks", None)
                chosen = None
                if world:
                    chosen = world[0]
                elif norm:
                    chosen = norm[0]
                if chosen is None:
                    continue
                pts = np.zeros((NUM_LANDMARKS, 3), dtype=float)
                vrow = np.zeros(NUM_LANDMARKS, dtype=float)
                for i, lm in enumerate(chosen):
                    if i >= NUM_LANDMARKS:
                        break
                    pts[i] = (lm.x, -lm.y, getattr(lm, "z", 0.0))
                    vrow[i] = getattr(lm, "visibility", 1.0)
                frames.append(pts)
                vis.append(vrow)
        cap.release()
        return self._finish(frames, vis, fps, video_path, "tasks")


def estimate_from_video(
    video_path: str,
    model_size: str = "full",
    backend: str = "mediapipe",
    **kwargs,
) -> PoseSequence:
    """Extract a PoseSequence from a video using the chosen backend.

    backend : 'mediapipe' (default, always available) or 'rtmpose' (highest
              accuracy; needs `pip install rtmlib onnxruntime`). If 'rtmpose'
              fails for any reason, automatically falls back to MediaPipe.
    """
    if backend == "rtmpose":
        try:
            from .rtmpose_backend import estimate_rtmpose
            return estimate_rtmpose(video_path)
        except Exception as exc:  # graceful fallback
            seq = PoseEstimator(model_size=model_size, **kwargs).estimate(video_path)
            seq.meta["backend_note"] = (
                f"rtmpose unavailable ({type(exc).__name__}); used mediapipe:{model_size}. "
                f"Install with: pip install rtmlib onnxruntime"
            )
            return seq
    return PoseEstimator(model_size=model_size, **kwargs).estimate(video_path)
