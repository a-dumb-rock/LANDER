from landr.scoring.less import score_less
from landr.scoring.risk import assess_risk


def _metrics(kf_ic, kv_ic, trunk_ic, kf_low, kv_low, disp, peak_l, peak_r, asym):
    return {
        "at_initial_contact": {"knee_flexion_deg": kf_ic, "knee_valgus_deg": kv_ic, "trunk_flexion_deg": trunk_ic},
        "at_lowest_point": {"knee_flexion_deg": kf_low, "knee_valgus_deg": kv_low},
        "knee_flexion_displacement_deg": disp,
        "peak_valgus_deg": {"left": peak_l, "right": peak_r},
        "asymmetry_index": asym,
    }


def test_perfect_landing_scores_zero():
    m = _metrics(45, 2, 30, 95, 3, 60, 2, 2, 0.02)
    less = score_less(m)
    assert less.total == 0
    assert assess_risk(less, m).category == "low"


def test_bad_landing_scores_high():
    m = _metrics(15, 20, 3, 25, 22, 10, 25, 24, 0.4)
    less = score_less(m)
    assert less.total >= 5
    risk = assess_risk(less, m)
    assert risk.category == "high"


def test_risk_score_bounded():
    m = _metrics(15, 30, 0, 20, 30, 5, 40, 40, 0.9)
    risk = assess_risk(score_less(m), m)
    assert 0.0 <= risk.score_0_100 <= 100.0
