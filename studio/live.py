"""LANDR Studio — live multi-camera streaming and real-time rep detection.

Architecture
────────────
  CameraStream   one thread per camera, reads frames from webcam/RTSP into a
                 bounded deque (most-recent N frames kept).
  LiveSession    coordinator: syncs frames across cameras by wall-clock time,
                 runs RTMPose on each synced set, triangulates to 3D, feeds a
                 hip-height state machine to detect rep completion, then calls
                 back with the reconstructed PoseSequence.
  RepCallback    user-supplied callable(AnalysisResult) fired after each rep.

The landing detector is a simple 3-state FSM:
  IDLE -> FALLING (hip drops > threshold) -> RECOVERING (hip rises after min)
When the hip is stable for SETTLE_S seconds after the minimum, the buffered
frames from just before the drop through stabilisation are extracted, analysed
through the full Studio pipeline, and emitted via the callback.

GPU / backend note (AMD RX 6600 on Windows)
────────────────────────────────────────────
rtmlib wraps ONNX Runtime. To use the RX 6600 on Windows:
  pip install onnxruntime-directml
  LiveSession(..., device='dml')

'cpu' is the safe default; 'dml' enables DirectML acceleration. On a modern
CPU 4×30fps is feasible; DML takes it to 4×60fps comfortably.
"""

from __future__ import annotations

import queue
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable

import numpy as np

from landr import config
from landr.biomechanics import compute_metrics, detect_landing_events
from landr.scoring import assess_risk, score_less
from landr.types import AnalysisResult, PoseSequence

from .anatomical import to_anatomical
from .calibration import CameraRig
from .triangulation import triangulate_sequence


# ---------------------------------------------------------------------------
# Frame container
# ---------------------------------------------------------------------------

@dataclass
class Frame:
    bgr: np.ndarray       # H×W×3 BGR image
    t: float              # wall-clock time (time.monotonic())
    idx: int              # frame counter within this stream


# ---------------------------------------------------------------------------
# Per-camera capture thread
# ---------------------------------------------------------------------------

class CameraStream:
    """Captures frames from one camera in a background thread.

    source: int (webcam index) or str (RTSP / file URL).
    maxlen: rolling buffer size (most-recent frames kept).
    """

    def __init__(self, source: int | str, maxlen: int = 300) -> None:
        self.source = source
        self._buf: deque[Frame] = deque(maxlen=maxlen)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self.fps: float = 30.0
        self.ok = False

    def start(self) -> "CameraStream":
        self._thread = threading.Thread(target=self._run, daemon=True, name=f"cam-{self.source}")
        self._thread.start()
        # Wait up to 3 s for the first frame.
        deadline = time.monotonic() + 3.0
        while not self.ok and time.monotonic() < deadline:
            time.sleep(0.05)
        return self

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2.0)

    def latest(self) -> Frame | None:
        with self._lock:
            return self._buf[-1] if self._buf else None

    def frames_since(self, t: float) -> list[Frame]:
        with self._lock:
            return [f for f in self._buf if f.t >= t]

    def _run(self) -> None:
        import cv2  # type: ignore
        cap = cv2.VideoCapture(self.source)
        if not cap.isOpened():
            return
        fps = cap.get(cv2.CAP_PROP_FPS)
        self.fps = fps if fps > 0 else 30.0
        idx = 0
        while not self._stop.is_set():
            ok, bgr = cap.read()
            if not ok:
                time.sleep(0.01)
                continue
            f = Frame(bgr=bgr, t=time.monotonic(), idx=idx)
            with self._lock:
                self._buf.append(f)
            self.ok = True
            idx += 1
        cap.release()


# ---------------------------------------------------------------------------
# Landing FSM
# ---------------------------------------------------------------------------

_FALL_THRESH  = 0.04   # metres hip drop to trigger FALLING state
_SETTLE_S     = 0.35   # seconds hip stable → rep complete
_PRE_BUFFER_S = 0.5    # seconds of 3D history kept before the drop starts


class _LandingFSM:
    """Three-state (IDLE / FALLING / RECOVERING) hip-height monitor."""

    def __init__(self) -> None:
        self._state = "IDLE"
        self._baseline_y: float | None = None
        self._min_y: float = 0.0
        self._min_t: float = 0.0
        self._drop_t: float = 0.0
        self._settle_start: float | None = None

    def update(self, hip_y: float, t: float) -> bool:
        """Feed current hip height; returns True when a rep is complete."""
        if self._baseline_y is None:
            self._baseline_y = hip_y
            return False

        # Smooth the baseline slowly upward (athlete standing between reps).
        if self._state == "IDLE":
            self._baseline_y = 0.95 * self._baseline_y + 0.05 * max(hip_y, self._baseline_y)

        if self._state == "IDLE":
            if hip_y < self._baseline_y - _FALL_THRESH:
                self._state = "FALLING"
                self._min_y = hip_y
                self._min_t = t
                self._drop_t = t
                self._settle_start = None
            return False

        if self._state == "FALLING":
            if hip_y < self._min_y:
                self._min_y = hip_y
                self._min_t = t
            elif hip_y > self._min_y + 0.01:
                self._state = "RECOVERING"
                self._settle_start = None
            return False

        if self._state == "RECOVERING":
            if hip_y < self._min_y + 0.005:
                # Dipped again — not stable yet.
                self._settle_start = None
            else:
                if self._settle_start is None:
                    self._settle_start = t
                elif t - self._settle_start >= _SETTLE_S:
                    # Rep complete.
                    self._state = "IDLE"
                    self._baseline_y = hip_y
                    self._settle_start = None
                    return True
        return False

    @property
    def drop_t(self) -> float:
        return self._drop_t


# ---------------------------------------------------------------------------
# Live session
# ---------------------------------------------------------------------------

@dataclass
class LiveStatus:
    """Real-time status pushed to the dashboard on every processed frame."""
    frame: int
    t: float
    fps: float
    state: str          # IDLE / FALLING / RECOVERING
    hip_y: float
    cameras_ok: list[bool]


class LiveSession:
    """Coordinate N camera streams, detect reps, emit AnalysisResult per rep.

    Parameters
    ----------
    sources:   list of webcam indices (int) or RTSP/file URLs (str).
    rig:       calibrated CameraRig matching the source order.
    on_rep:    called with AnalysisResult each time a rep completes.
    on_frame:  optional; called with LiveStatus on each processed frame.
    fps_limit: cap the processing rate (default 30 fps).
    device:    'cpu' or 'dml' (DirectML for AMD/Intel GPU on Windows).
    """

    def __init__(
        self,
        sources: list[int | str],
        rig: CameraRig,
        on_rep: Callable[[AnalysisResult], None],
        on_frame: Callable[[LiveStatus], None] | None = None,
        fps_limit: float = 30.0,
        device: str = "cpu",
        athlete: dict[str, Any] | None = None,
    ) -> None:
        if len(sources) != len(rig.cameras):
            raise ValueError(f"sources ({len(sources)}) must match rig cameras ({len(rig.cameras)})")
        self.sources = sources
        self.rig = rig
        self.on_rep = on_rep
        self.on_frame = on_frame
        self.fps_limit = fps_limit
        self.device = device
        self.athlete = athlete or {}

        self._streams: list[CameraStream] = []
        self._detector = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

        # Rolling 3D buffer: list of (t, landmarks_J×3)
        self._buf3d: deque[tuple[float, np.ndarray]] = deque()
        self._fsm = _LandingFSM()
        self._frame_idx = 0

    # ---- public API --------------------------------------------------------

    def start(self) -> "LiveSession":
        """Open cameras and start the processing thread."""
        from .detector import RTMPoseDetector
        self._detector = RTMPoseDetector(
            mode="performance",
            device=self.device,
        )
        self._streams = [CameraStream(s).start() for s in self.sources]
        bad = [i for i, s in enumerate(self._streams) if not s.ok]
        if bad:
            raise RuntimeError(f"Could not open camera(s): {bad}")
        self._thread = threading.Thread(target=self._loop, daemon=True, name="live-session")
        self._thread.start()
        return self

    def stop(self) -> None:
        self._stop.set()
        for s in self._streams:
            s.stop()
        if self._thread:
            self._thread.join(timeout=3.0)

    # ---- processing loop ---------------------------------------------------

    def _loop(self) -> None:
        period = 1.0 / self.fps_limit
        while not self._stop.is_set():
            t0 = time.monotonic()
            self._tick()
            elapsed = time.monotonic() - t0
            wait = period - elapsed
            if wait > 0:
                time.sleep(wait)

    def _tick(self) -> None:
        # 1. Grab the most-recent frame from each camera (best-effort sync).
        frames = [s.latest() for s in self._streams]
        if any(f is None for f in frames):
            return

        t_now = time.monotonic()

        # 2. Run RTMPose on each frame BGR.
        kps_list: list[np.ndarray] = []
        conf_list: list[np.ndarray] = []
        for frm, cam in zip(frames, self.rig.cameras):
            kp1, sc1 = self._detect_frame(frm.bgr)
            kps_list.append(kp1)
            conf_list.append(sc1)

        # kp_stack: (M, 1, J, 2)  conf_stack: (M, 1, J)
        kp_stack  = np.stack([k[None] for k in kps_list])
        cf_stack  = np.stack([c[None] for c in conf_list])

        pts3d, _  = triangulate_sequence(
            self.rig.cameras, kp_stack, cf_stack, robust=False
        )
        # pts3d: (1, J, 3) → (J, 3)
        joints3d  = pts3d[0]

        # 3. Append to rolling buffer (prune older than PRE_BUFFER_S + 2 s).
        self._buf3d.append((t_now, joints3d))
        cutoff = t_now - (_PRE_BUFFER_S + 2.0)
        while self._buf3d and self._buf3d[0][0] < cutoff:
            self._buf3d.popleft()

        # 4. Hip height for the FSM (mean of left+right hip).
        lh = joints3d[config.LEFT_HIP]
        rh = joints3d[config.RIGHT_HIP]
        hip_y = float(np.nanmean([lh[1], rh[1]]))

        rep_done = self._fsm.update(hip_y, t_now)

        # 5. Notify frame callback.
        if self.on_frame:
            self.on_frame(LiveStatus(
                frame=self._frame_idx,
                t=t_now,
                fps=self.fps_limit,
                state=self._fsm._state,
                hip_y=hip_y,
                cameras_ok=[s.ok for s in self._streams],
            ))

        self._frame_idx += 1

        # 6. Analyse completed rep.
        if rep_done:
            self._analyse_rep(self._fsm.drop_t)

    def _detect_frame(self, bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Run RTMPose on one BGR frame; return (kp J×2, conf J)."""
        pts = np.zeros((config.NUM_LANDMARKS, 2), float)
        crow = np.zeros(config.NUM_LANDMARKS, float)
        try:
            kps, scores = self._detector._model(bgr)
            if kps is not None and len(kps) > 0:
                from .detector import _COCO_TO_LANDR
                pi = int(np.argmax(scores.mean(axis=1))) if len(kps) > 1 else 0
                for ci, li in _COCO_TO_LANDR.items():
                    if ci < len(kps[pi]):
                        pts[li] = kps[pi][ci]
                        crow[li] = float(scores[pi][ci])
        except Exception:
            pass
        return pts, crow

    def _analyse_rep(self, drop_t: float) -> None:
        """Extract buffered 3D frames around the rep and run the clinical engine."""
        # Grab frames from PRE_BUFFER_S before the drop to now.
        window_start = drop_t - _PRE_BUFFER_S
        frames = [(t, j) for t, j in self._buf3d if t >= window_start]
        if len(frames) < 8:
            return

        lms = np.stack([j for _, j in frames])   # (T, J, 3)
        fps = self.fps_limit
        if len(frames) > 1:
            dt = frames[-1][0] - frames[0][0]
            fps = (len(frames) - 1) / dt if dt > 0 else fps

        world = PoseSequence(
            landmarks=lms, fps=fps,
            meta={"source": "live", "frame": "world", "n_views": len(self._streams)},
        )
        anatomical = to_anatomical(world, self.rig.up)

        try:
            events  = detect_landing_events(anatomical)
            metrics = compute_metrics(anatomical, events)
            less    = score_less(metrics)
            risk    = assess_risk(less, metrics)
        except Exception as exc:
            print(f"[live] analysis error: {exc}")
            return

        result = AnalysisResult(
            metrics=metrics, events=events, less=less, risk=risk,
            meta={
                "product": "studio",
                "mode": "live",
                "n_views": len(self._streams),
                "athlete": self.athlete,
            },
        )
        self.on_rep(result)


# ---------------------------------------------------------------------------
# Async WebSocket bridge (for server.py)
# ---------------------------------------------------------------------------

class LiveBridge:
    """Thread-safe bridge between LiveSession (threads) and asyncio WebSocket."""

    def __init__(self) -> None:
        self._q: queue.Queue = queue.Queue(maxsize=256)
        self._session: LiveSession | None = None

    def push_frame(self, status: LiveStatus) -> None:
        msg = {
            "type": "frame",
            "frame": status.frame,
            "state": status.state,
            "hip_y": round(status.hip_y, 4),
            "cameras_ok": status.cameras_ok,
        }
        try:
            self._q.put_nowait(msg)
        except queue.Full:
            pass

    def push_rep(self, result: AnalysisResult) -> None:
        msg = {"type": "rep", "result": result.as_dict()}
        self._q.put_nowait(msg)

    async def recv(self):
        """Async-friendly: pull next message (blocks event loop for ≤10ms)."""
        import asyncio
        while True:
            try:
                return self._q.get_nowait()
            except queue.Empty:
                await asyncio.sleep(0.01)

    def start(
        self,
        sources: list[int | str],
        rig: CameraRig,
        athlete: dict | None = None,
        device: str = "cpu",
    ) -> None:
        if self._session:
            self._session.stop()
        self._session = LiveSession(
            sources=sources,
            rig=rig,
            on_rep=self.push_rep,
            on_frame=self.push_frame,
            athlete=athlete or {},
            device=device,
        ).start()

    def stop(self) -> None:
        if self._session:
            self._session.stop()
            self._session = None

    @property
    def running(self) -> bool:
        return self._session is not None
