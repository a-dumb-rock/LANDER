"""Camera model and rig calibration for LANDR Studio.

A :class:`Camera` is a standard pinhole model: intrinsics ``K`` (3x3) and extrinsics
``R`` (3x3 world->camera rotation) and ``t`` (3, world->camera translation). Its
projection matrix is ``P = K [R | t]``. A :class:`CameraRig` is a set of such cameras
plus the world "up" direction (known when you physically set the rig up), which
Studio uses to build the athlete's anatomical frame.

Two ways to obtain calibration in practice:
  * **Known geometry** — for a bench rig you measure/CAD the camera poses.
  * **DLT from correspondences** — image a calibration object with known 3D points
    (a checkerboard / wand) and solve each camera's ``P`` from >=6 point pairs via
    :func:`calibrate_dlt`. This is the standard Direct Linear Transform.

Everything here is plain numpy so it runs anywhere; nothing is fit to ground-truth
angles, only to physical calibration data.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

_EPS = 1e-9


@dataclass
class Camera:
    """A calibrated pinhole camera.

    K : (3,3) intrinsics [[fx,0,cx],[0,fy,cy],[0,0,1]]
    R : (3,3) world->camera rotation (orthonormal)
    t : (3,)  world->camera translation
    name : label for reports.
    image_size : (width, height) in pixels, for sanity checks / viz.
    """

    K: np.ndarray
    R: np.ndarray
    t: np.ndarray
    name: str = "cam"
    image_size: tuple[int, int] = (1920, 1080)

    def __post_init__(self) -> None:
        self.K = np.asarray(self.K, float).reshape(3, 3)
        self.R = np.asarray(self.R, float).reshape(3, 3)
        self.t = np.asarray(self.t, float).reshape(3)

    @property
    def P(self) -> np.ndarray:
        """3x4 projection matrix ``K [R | t]``."""
        return self.K @ np.hstack([self.R, self.t.reshape(3, 1)])

    @property
    def center(self) -> np.ndarray:
        """Camera centre in world coordinates: ``-R^T t``."""
        return -self.R.T @ self.t

    def project(self, points_world: np.ndarray) -> np.ndarray:
        """Project world points (..., 3) to pixel coordinates (..., 2).

        Points behind the camera (non-positive depth) still return a value but are
        flagged by :meth:`visible`; callers that care should mask on depth.
        """
        pts = np.asarray(points_world, float)
        flat = pts.reshape(-1, 3)
        cam = (self.R @ flat.T + self.t.reshape(3, 1)).T  # (N,3) camera coords
        z = np.clip(cam[:, 2:3], _EPS, None)
        img = (self.K @ (cam / z).T).T  # (N,3)
        out = img[:, :2].reshape(pts.shape[:-1] + (2,))
        return out

    def depth(self, points_world: np.ndarray) -> np.ndarray:
        """Camera-frame Z (depth) of world points; >0 means in front of the lens."""
        pts = np.asarray(points_world, float).reshape(-1, 3)
        cam = (self.R @ pts.T + self.t.reshape(3, 1)).T
        return cam[:, 2]

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "K": self.K.tolist(),
            "R": self.R.tolist(),
            "t": self.t.tolist(),
            "image_size": list(self.image_size),
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Camera":
        return cls(
            K=np.array(d["K"], float),
            R=np.array(d["R"], float),
            t=np.array(d["t"], float),
            name=d.get("name", "cam"),
            image_size=tuple(d.get("image_size", (1920, 1080))),
        )


@dataclass
class CameraRig:
    """A set of calibrated cameras plus the world up-direction.

    ``up`` is the world-space unit vector pointing against gravity. You know it when
    you install the rig (e.g. +Z if cameras sit on the floor plane). Studio uses it
    to orient the anatomical frame, so a landing's frontal plane is measured
    correctly regardless of how the athlete faces the cameras.
    """

    cameras: list[Camera]
    up: np.ndarray = field(default_factory=lambda: np.array([0.0, 0.0, 1.0]))

    def __post_init__(self) -> None:
        self.up = np.asarray(self.up, float).reshape(3)
        n = np.linalg.norm(self.up)
        if n < _EPS:
            raise ValueError("rig 'up' vector must be non-zero")
        self.up = self.up / n
        if len(self.cameras) < 2:
            raise ValueError("a Studio rig needs >= 2 calibrated cameras for 3D")

    def __len__(self) -> int:
        return len(self.cameras)

    def to_dict(self) -> dict[str, Any]:
        return {"up": self.up.tolist(), "cameras": [c.to_dict() for c in self.cameras]}

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "CameraRig":
        return cls(
            cameras=[Camera.from_dict(c) for c in d["cameras"]],
            up=np.array(d.get("up", [0.0, 0.0, 1.0]), float),
        )

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.to_dict(), indent=2))

    @classmethod
    def load(cls, path: str | Path) -> "CameraRig":
        return cls.from_dict(json.loads(Path(path).read_text()))


def look_at(eye: np.ndarray, target: np.ndarray, up: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Build world->camera (R, t) for a camera at ``eye`` looking at ``target``.

    Uses the standard right-handed convention with +Z pointing from the camera into
    the scene (OpenCV style), so projected depth is positive in front of the lens.
    """
    eye = np.asarray(eye, float)
    target = np.asarray(target, float)
    up = np.asarray(up, float)

    forward = target - eye
    forward = forward / (np.linalg.norm(forward) + _EPS)
    right = np.cross(forward, up)
    right = right / (np.linalg.norm(right) + _EPS)
    true_up = np.cross(right, forward)

    # Camera axes as rows: x=right, y=-true_up (image y grows downward), z=forward.
    R = np.stack([right, -true_up, forward], axis=0)
    t = -R @ eye
    return R, t


def make_arc_rig(
    n_cameras: int = 4,
    radius: float = 3.0,
    height: float = 1.2,
    target: tuple[float, float, float] = (0.0, 0.0, 1.0),
    arc_deg: float = 160.0,
    fx: float = 1400.0,
    image_size: tuple[int, int] = (1920, 1080),
    up: tuple[float, float, float] = (0.0, 0.0, 1.0),
) -> CameraRig:
    """Construct a synthetic multi-camera rig on a horizontal arc around the athlete.

    Handy for demos and for the self-test. World convention: +Z is up, athlete
    stands near the origin facing +Y. Cameras sit at ``height`` on an arc of
    ``arc_deg`` centred on the athlete's front, all looking at ``target``.
    """
    up_v = np.array(up, float)
    tgt = np.array(target, float)
    cx, cy = image_size[0] / 2.0, image_size[1] / 2.0
    K = np.array([[fx, 0, cx], [0, fx, cy], [0, 0, 1]], float)

    cams: list[Camera] = []
    start = -np.radians(arc_deg) / 2.0
    step = np.radians(arc_deg) / max(1, n_cameras - 1)
    for i in range(n_cameras):
        ang = start + i * step
        # Place cameras in front of the athlete (-Y side), fanned around the arc.
        eye = np.array([radius * np.sin(ang), -radius * np.cos(ang), height], float)
        R, t = look_at(eye, tgt, up_v)
        cams.append(Camera(K=K, R=R, t=t, name=f"cam{i}", image_size=image_size))
    return CameraRig(cameras=cams, up=up_v)


def calibrate_dlt(points_world: np.ndarray, points_image: np.ndarray) -> np.ndarray:
    """Estimate a 3x4 projection matrix from >=6 3D<->2D correspondences (DLT).

    Returns ``P`` such that ``[u v 1]^T ~ P [X Y Z 1]^T``. Points are normalised for
    numerical conditioning (Hartley). This is the standard camera-resectioning step
    you run once per camera against a checkerboard/wand of known geometry.
    """
    X = np.asarray(points_world, float)
    x = np.asarray(points_image, float)
    if X.shape[0] < 6:
        raise ValueError("DLT needs >= 6 point correspondences")

    # Hartley normalisation of both spaces.
    def _norm(pts: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        c = pts.mean(axis=0)
        d = np.sqrt(((pts - c) ** 2).sum(axis=1)).mean() + _EPS
        s = np.sqrt(pts.shape[1]) / d
        dim = pts.shape[1]
        T = np.eye(dim + 1)
        T[:dim, :dim] *= s
        T[:dim, dim] = -s * c
        homo = np.hstack([pts, np.ones((pts.shape[0], 1))])
        return (T @ homo.T).T[:, :dim], T

    Xn, TX = _norm(X)
    xn, Tx = _norm(x)

    rows = []
    for (Xi, xi) in zip(Xn, xn):
        Xh = np.append(Xi, 1.0)
        u, v = xi
        rows.append(np.concatenate([np.zeros(4), -Xh, v * Xh]))
        rows.append(np.concatenate([Xh, np.zeros(4), -u * Xh]))
    A = np.array(rows)
    _, _, Vt = np.linalg.svd(A)
    Pn = Vt[-1].reshape(3, 4)

    # Denormalise: x = Tx^-1 Pn TX.
    P = np.linalg.inv(Tx) @ Pn @ TX
    return P / (P[2, 3] if abs(P[2, 3]) > _EPS else 1.0)
