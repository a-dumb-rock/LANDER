"""Core data structures shared across the pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any

import numpy as np


@dataclass
class PoseSequence:
    """A time series of 3D body landmarks.

    landmarks : np.ndarray, shape (T, J, 3)  per-frame (x, y, z) for J landmarks.
    fps       : frames per second of the source video.
    visibility: np.ndarray, shape (T, J), per-landmark confidence in [0, 1].
    meta      : free-form provenance.
    """

    landmarks: np.ndarray
    fps: float
    visibility: np.ndarray | None = None
    meta: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.landmarks = np.asarray(self.landmarks, dtype=float)
        if self.landmarks.ndim != 3 or self.landmarks.shape[2] != 3:
            raise ValueError(
                f"landmarks must have shape (T, J, 3); got {self.landmarks.shape}"
            )
        if self.visibility is None:
            self.visibility = np.ones(self.landmarks.shape[:2], dtype=float)
        else:
            self.visibility = np.asarray(self.visibility, dtype=float)

    @property
    def n_frames(self) -> int:
        return self.landmarks.shape[0]

    @property
    def n_landmarks(self) -> int:
        return self.landmarks.shape[1]

    def time(self) -> np.ndarray:
        return np.arange(self.n_frames) / float(self.fps)

    def point(self, frame: int, idx: int) -> np.ndarray:
        return self.landmarks[frame, idx]


@dataclass
class LandingEvents:
    """Key frames within the landing phase of a drop-vertical jump."""

    initial_contact: int
    lowest_point: int
    stabilized: int
    notes: str = ""

    def __post_init__(self) -> None:
        self.initial_contact = int(self.initial_contact)
        self.lowest_point = int(self.lowest_point)
        self.stabilized = int(self.stabilized)

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class LessItem:
    """A single Landing Error Scoring System criterion result."""

    key: str
    description: str
    error: bool
    value: float | None
    detail: str = ""

    def __post_init__(self) -> None:
        # Cast to native Python types so results are always JSON-serializable.
        self.error = bool(self.error)
        if self.value is not None:
            self.value = float(self.value)

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class LessResult:
    items: list[LessItem]
    total: int

    def as_dict(self) -> dict[str, Any]:
        return {"total": self.total, "items": [i.as_dict() for i in self.items]}

    def errors(self) -> list[LessItem]:
        return [i for i in self.items if i.error]


@dataclass
class RiskResult:
    category: str
    score_0_100: float
    less_total: int
    rationale: str

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class AnalysisResult:
    """The complete output of the LANDR pipeline."""

    metrics: dict[str, Any]
    events: LandingEvents
    less: LessResult
    risk: RiskResult
    report: str = ""
    report_provider: str = "mock"
    meta: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {
            "metrics": self.metrics,
            "events": self.events.as_dict(),
            "less": self.less.as_dict(),
            "risk": self.risk.as_dict(),
            "report": self.report,
            "report_provider": self.report_provider,
            "meta": self.meta,
        }
