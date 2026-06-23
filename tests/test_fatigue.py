"""Tests for the fatigue module (Pillar 2)."""

from landr.fatigue import compare
from landr.pipeline import analyze_sequence
from landr.synthetic import synthetic_jump


def _pair(level):
    fresh = analyze_sequence(synthetic_jump(quality="good", fatigue=0.0, seed=1))
    fatigued = analyze_sequence(synthetic_jump(quality="good", fatigue=level, seed=1))
    return fresh, fatigued


def test_fatigue_increases_vulnerability():
    fresh, fatigued = _pair(0.8)
    cmp = compare(fresh, fatigued)
    assert cmp.vulnerability_score > 0
    # Valgus should rise under fatigue.
    assert cmp.deltas["peak_valgus_increase_deg"] > 0


def test_no_fatigue_is_low_vulnerability():
    fresh, same = _pair(0.0)
    cmp = compare(fresh, same)
    assert cmp.vulnerability_score < 25
    assert cmp.category == "robust"


def test_more_fatigue_more_vulnerable():
    fresh = analyze_sequence(synthetic_jump(quality="good", fatigue=0.0, seed=1))
    mild = analyze_sequence(synthetic_jump(quality="good", fatigue=0.3, seed=1))
    severe = analyze_sequence(synthetic_jump(quality="good", fatigue=0.9, seed=1))
    assert compare(fresh, severe).vulnerability_score >= compare(fresh, mild).vulnerability_score


def test_fatigue_comparison_json_serializable():
    import json
    fresh, fatigued = _pair(0.7)
    json.dumps(compare(fresh, fatigued).as_dict())
