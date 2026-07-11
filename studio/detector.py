"""Per-view 2D keypoint detection for Studio (feeds triangulation).

Studio triangulates 2D keypoints from several cameras, so each view needs 2D pixel
coordinates + confidences in a shared joint indexing (LANDR's MediaPipe-33). This
module provides:

  * :class:`RTMPoseDetector` — the real detector, reusing the same rtmlib backend as
    LANDR Mobile (COCO-17 -> LANDR-33), but returning raw *pixel* coordinates (not
    y-flipped) because triangulation needs true image coordinates.
  * :func:`keypoints_from_arrays` — wrap precomputed keypoints (from any source,
    including the synthetic projector) so the pipeline is testable without video.

The real path is import-lazy: this module imports fine without rtmlib/opencv; only
calling :meth:`RTMPoseDetector.run` needs them. That keeps the whole Studio package
runnable (self-test, demo, dashboard) on a machine with just numpy.
"""

from __future__ import annotations

import numpy as np

from landr import config

# COCO-17 -> LANDR/MediaPipe-33 index map (same as the mobile backend).
_COCO_TO_LANDR = {
    0: config.NOSE,
    5: config.LEFT_SHOULDER,
    6: config.RIGHT_SHOULDER,
    11: config.LEFT_HIP,
    12: config.RIGHT_HIP,
    13: config.LEFT_KNEE,
    14: config.RIGHT_KNEE,
    15: config.LEFT_ANKLE,
    16: config.RIGHT_ANKLE,
}


class RTMPoseDetector:
    """Detect LANDR-33 2D keypoints per frame of a single view's video.

    device: 'cpu' (default) or 'dml' (DirectML — AMD/Intel GPU on Windows,
    requires ``pip install onnxruntime-directml``).
    """

    def __init__(self, mode: str = "performance", device: str = "cpu") -> None:
        self.mode = mode
        self.device = device
        self._model = None   # lazy-initialised on first use

    def _get_model(self):
        if self._model is None:
            from rtmlib import Body  # type: ignore
            self._model = Body(
                mode=self.mode,
                to_openpose=False,
                backend="onnxruntime",
                device=self.device,
            )
        return self._model

    def run(self, video_path: str) -> tuple[np.ndarray, np.ndarray, float]:
        """Return ``(keypoints, confidences, fps)``.

        keypoints   : (T, J, 2) pixel coordinates (image convention, y downward).
        confidences : (T, J) keypoint scores in [0, 1].
        """
        import cv2  # type: ignore

        model = self._get_model()
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise FileNotFoundError(f"Could not open video: {video_path}")
        fps = cap.get(cv2.CAP_PROP_FPS) or 60.0

        frames: list[np.ndarray] = []
        confs: list[np.ndarray] = []
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            keypoints, scores = model(frame_bgr)  # type: ignore
            pts = np.full((config.NUM_LANDMARKS, 2), np.nan)
            crow = np.zeros(config.NUM_LANDMARKS)
            if keypoints is not None and len(keypoints) > 0:
                person = int(np.argmax(scores.mean(axis=1))) if len(keypoints) > 1 else 0
                kp, sc = keypoints[person], scores[person]
                for coco_i, landr_i in _COCO_TO_LANDR.items():
                    if coco_i < len(kp):
                        pts[landr_i] = kp[coco_i]
                        crow[landr_i] = float(sc[coco_i])
            frames.append(pts)
            confs.append(crow)
        cap.release()
        if not frames:
            raise ValueError(f"No frames decoded from {video_path}")
        return np.stack(frames), np.stack(confs), float(fps)


def keypoints_from_arrays(
    keypoints: np.ndarray, confidences: np.ndarray | None = None
) -> tuple[np.ndarray, np.ndarray]:
    """Validate/normalise precomputed per-view keypoints for the pipeline."""
    kp = np.asarray(keypoints, float)
    if kp.ndim != 3 or kp.shape[2] != 2:
        raise ValueError(f"keypoints must be (T, J, 2); got {kp.shape}")
    if confidences is None:
        confidences = np.ones(kp.shape[:2])
    return kp, np.asarray(confidences, float)
