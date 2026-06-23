"""Scripted end-to-end demo. Run:  python examples/run_demo.py

Shows the LANDR pipeline plus the two v2 capabilities: the fatigue comparison
(Pillar 2) and the accuracy benchmark (Pillar 1).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from landr.pipeline import analyze_sequence  # noqa: E402
from landr.synthetic import synthetic_jump  # noqa: E402
from landr.fatigue import compare  # noqa: E402
from landr.accuracy import run_accuracy_benchmark  # noqa: E402


def basic(quality):
    res = analyze_sequence(synthetic_jump(quality=quality), athlete={"name": f"Demo ({quality})"})
    print(f"[{quality}] risk={res.risk.category} score={res.risk.score_0_100} LESS={res.less.total}")


def fatigue_demo():
    fresh = analyze_sequence(synthetic_jump(quality="good", fatigue=0.0, seed=1))
    fatigued = analyze_sequence(synthetic_jump(quality="good", fatigue=0.8, seed=1))
    cmp = compare(fresh, fatigued)
    print(f"[fatigue] vulnerability={cmp.vulnerability_score}/100 ({cmp.category})")
    print(f"          deltas={cmp.deltas}")


def accuracy_demo():
    res = run_accuracy_benchmark()
    print(f"[accuracy] valgus  naive={res['valgus']['naive_rmse_deg']}° "
          f"improved={res['valgus']['improved_rmse_deg']}° "
          f"(-{res['valgus']['reduction_pct']}%)")


if __name__ == "__main__":
    basic("good")
    basic("poor")
    fatigue_demo()
    accuracy_demo()
