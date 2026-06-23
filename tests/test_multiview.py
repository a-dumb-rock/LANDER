"""Tests for two-view fusion (accuracy upgrade)."""

import json

from landr.multiview import analyze_two_view_sequences, fuse_metrics
from landr.biomechanics import compute_metrics, detect_landing_events
from landr.synthetic import synthetic_jump
from landr.types import AnalysisResult


def _metrics(seq):
    return compute_metrics(seq, detect_landing_events(seq))


def test_fusion_takes_valgus_from_front_flexion_from_side():
    front = _metrics(synthetic_jump(quality="poor", seed=1))   # lots of valgus
    side = _metrics(synthetic_jump(quality="good", seed=2))    # lots of flexion
    fused = fuse_metrics(front, side)
    # valgus should match the front source; flexion should match the side source
    assert fused["peak_valgus_deg"] == front["peak_valgus_deg"]
    assert (fused["knee_flexion_displacement_deg"]
            == side["knee_flexion_displacement_deg"])


def test_two_view_runs_and_serializes():
    front = synthetic_jump(quality="poor", seed=1)
    side = synthetic_jump(quality="poor", seed=2)
    res = analyze_two_view_sequences(front, side)
    assert isinstance(res, AnalysisResult)
    assert res.meta["mode"] == "two_view"
    json.dumps(res.as_dict())  # must be serializable


def test_fused_series_aligned_to_front_time():
    front = _metrics(synthetic_jump(quality="poor", seed=1, fps=60))
    side = _metrics(synthetic_jump(quality="good", seed=2, fps=30))
    fused = fuse_metrics(front, side)
    n = len(fused["series"]["time_s"])
    # all series resampled to the front time grid length
    assert len(fused["series"]["knee_flexion_left"]) == n
    assert len(fused["series"]["knee_valgus_left"]) == n
