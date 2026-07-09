"""Run LANDR on a real video and extract predicted angle series.

Produces the two series the benchmark compares against ground truth:

  * **naive**    — angles from the raw pose keypoints (no correction),
  * **improved** — angles after LANDR's accuracy pass (``accuracy.improve``:
    Savitzky-Golay temporal smoothing + limb-length constraint).

Both come from the *same* clip, so the reported "gain" is apples-to-apples. We use
``accuracy.valgus_series`` / ``flexion_series`` (which apply no internal smoothing)
so the benchmark alone controls smoothing.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from landr.accuracy import flexion_series, improve, valgus_series
from landr.pose import estimate_from_video
from landr.types import PoseSequence


@dataclass
class LandrAngles:
    fps: float
    time: np.ndarray
    naive: dict[str, dict[str, np.ndarray]]     # metric -> side -> series
    improved: dict[str, dict[str, np.ndarray]]
    meta: dict = field(default_factory=dict)


def angles_from_sequence(seq: PoseSequence) -> LandrAngles:
    """Compute naive and improved valgus/flexion series from a PoseSequence."""
    raw = np.asarray(seq.landmarks, float)
    imp = improve(raw)
    fps = float(seq.fps)
    t = np.arange(raw.shape[0]) / fps

    def bundle(landmarks: np.ndarray) -> dict[str, dict[str, np.ndarray]]:
        return {
            "valgus": {s: valgus_series(landmarks, s) for s in ("left", "right")},
            "flexion": {s: flexion_series(landmarks, s) for s in ("left", "right")},
        }

    return LandrAngles(
        fps=fps,
        time=t,
        naive=bundle(raw),
        improved=bundle(imp),
        meta=dict(seq.meta),
    )


def angles_from_video(
    video_path: str,
    backend: str = "rtmpose",
    cache_dir: str | None = None,
) -> LandrAngles:
    """Full path: video file -> LANDR pose -> naive/improved angle series.

    If cache_dir is given, raw landmarks are cached (keyed by video + backend)
    so repeated runs skip RTMPose inference entirely.  The angles are always
    recomputed from the landmarks, so changing improve() never requires cache
    invalidation — just re-run the benchmark.
    """
    import hashlib, os, pickle

    cache_path = None
    if cache_dir is not None:
        os.makedirs(cache_dir, exist_ok=True)
        key = hashlib.md5(f"{video_path}::{backend}::landmarks".encode()).hexdigest()
        cache_path = os.path.join(cache_dir, f"{key}.pkl")

    if cache_path is not None and os.path.exists(cache_path):
        with open(cache_path, "rb") as f:
            seq = pickle.load(f)
    else:
        seq = estimate_from_video(video_path, backend=backend)
        if cache_path is not None:
            with open(cache_path, "wb") as f:
                pickle.dump(seq, f)

    out = angles_from_sequence(seq)
    out.meta["video"] = video_path
    out.meta["backend"] = backend
    return out
