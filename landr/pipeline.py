"""End-to-end orchestration: PoseSequence (or video) -> AnalysisResult."""

from __future__ import annotations

from typing import Any

from .accuracy import improved_sequence
from .biomechanics import compute_metrics, detect_landing_events
from .reasoning.vlm import generate_report
from .scoring import assess_risk, score_less
from .types import AnalysisResult, PoseSequence


def analyze_sequence(
    seq: PoseSequence,
    athlete: dict[str, Any] | None = None,
    report_provider: str = "mock",
    report_model: str | None = None,
    refine: bool = False,
) -> AnalysisResult:
    """Run the full LANDR pipeline on an already-extracted pose sequence.

    refine : apply the accuracy pass (temporal smoothing + anatomical constraint)
             before measuring. Off for synthetic demos; on for real video.
    """
    if refine:
        seq = improved_sequence(seq)
    events = detect_landing_events(seq)
    metrics = compute_metrics(seq, events)
    less = score_less(metrics)
    risk = assess_risk(less, metrics)

    result = AnalysisResult(
        metrics=metrics, events=events, less=less, risk=risk,
        meta={"athlete": athlete or {}, "refined": refine, **seq.meta},
    )
    report, provider_used = generate_report(
        result, provider=report_provider, model=report_model, athlete=athlete
    )
    result.report = report
    result.report_provider = provider_used
    return result


def analyze(
    video_path: str,
    athlete: dict[str, Any] | None = None,
    report_provider: str = "mock",
    report_model: str | None = None,
    model_size: str = "full",
    backend: str = "mediapipe",
    refine: bool = True,
) -> AnalysisResult:
    """Run the full pipeline starting from a video file (requires mediapipe).

    model_size : 'lite' | 'full' | 'heavy' pose model.
    backend    : 'mediapipe' or 'rtmpose' (highest accuracy, see pose backend).
    refine     : apply the accuracy pass (recommended on for real video).
    """
    from .pose import estimate_from_video
    seq = estimate_from_video(video_path, model_size=model_size, backend=backend)
    return analyze_sequence(
        seq, athlete=athlete,
        report_provider=report_provider, report_model=report_model,
        refine=refine,
    )
