import json

from landr.pipeline import analyze_sequence
from landr.synthetic import synthetic_jump
from landr.types import AnalysisResult


def _run(quality):
    return analyze_sequence(synthetic_jump(quality=quality, seed=0))


def test_pipeline_runs_and_returns_result():
    res = _run("poor")
    assert isinstance(res, AnalysisResult)
    assert res.report
    assert res.report_provider == "mock"


def test_poor_is_riskier_than_good():
    good, poor = _run("good"), _run("poor")
    assert poor.less.total > good.less.total
    assert poor.risk.score_0_100 > good.risk.score_0_100


def test_good_landing_is_low_or_moderate():
    assert _run("good").risk.category in {"low", "moderate"}


def test_poor_landing_flags_valgus():
    flagged = {e.key for e in _run("poor").less.errors()}
    assert "peak_knee_valgus" in flagged


def test_events_ordered():
    ev = _run("poor").events
    assert ev.initial_contact <= ev.lowest_point <= ev.stabilized


def test_result_is_json_serializable():
    s = json.dumps(_run("good").as_dict())
    assert "risk" in s and "metrics" in s
