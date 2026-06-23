"""RTMPose backend (highest-accuracy single-camera keypoints).

RTMPose is the state-of-the-art 2D pose model used by sport tools like Sports2D —
more accurate than MediaPipe for athletic movement. This backend uses the
``rtmlib`` package (pip install rtmlib onnxruntime) and maps its COCO-17 keypoints
into LANDR's skeleton convention so the rest of the pipeline is unchanged.

RTMPose is 2D, which is exactly right for the two-view workflow: valgus from a
FRONT clip and knee/trunk flexion from a SIDE clip are both in-plane motions, so
2D-per-view keypoints give clean angles. Pair this backend with `analyze2` for the
best accuracy the codebase supports.

This module imports ``rtmlib`` lazily, so importing it never fails; only calling
:func:`estimate_rtmpose` requires the dependency.
"""

from __future__ import annotations

import numpy as np

from .. import config
from ..types import PoseSequence

# COCO-17 keypoint index -> LANDR (MediaPipe-33) index.
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


def estimate_rtmpose(video_path: str, mode: str = "performance") -> PoseSequence:
    """Run RTMPose over a video and return a :class:`PoseSequence`.

    mode : 'performance' (most accurate), 'balanced', or 'lightweight' (rtmlib).
    """
    import cv2  # type: ignore
    from rtmlib import Body  # type: ignore

    model = Body(mode=mode, to_openpose=False, backend="onnxruntime", device="cpu")

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise FileNotFoundError(f"Could not open video: {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0

    frames: list[np.ndarray] = []
    vis: list[np.ndarray] = []
    while True:
        ok, frame_bgr = cap.read()
        if not ok:
            break
        keypoints, scores = model(frame_bgr)  # (N,K,2), (N,K)
        if keypoints is None or len(keypoints) == 0:
            continue
        # Choose the most confident person.
        person = int(np.argmax(scores.mean(axis=1))) if len(keypoints) > 1 else 0
        kp = keypoints[person]
        sc = scores[person]

        pts = np.zeros((config.NUM_LANDMARKS, 3), dtype=float)
        vrow = np.zeros(config.NUM_LANDMARKS, dtype=float)
        for coco_i, landr_i in _COCO_TO_LANDR.items():
            if coco_i < len(kp):
                x, y = kp[coco_i]
                # Flip y so "up" is positive (image y grows downward). z=0 (2D).
                pts[landr_i] = (float(x), -float(y), 0.0)
                vrow[landr_i] = float(sc[coco_i])
        frames.append(pts)
        vis.append(vrow)
    cap.release()

    if not frames:
        raise ValueError(
            f"No pose detected in {video_path}. Is a full body visible and well-lit?"
        )

    return PoseSequence(
        landmarks=np.stack(frames),
        fps=float(fps),
        visibility=np.stack(vis),
        meta={"source": video_path, "estimator": f"rtmpose:{mode}", "fps": float(fps)},
    )
