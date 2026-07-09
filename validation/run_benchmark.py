"""Run the full real-data accuracy benchmark and print results.

Usage:
    python -m validation.run_benchmark
    python -m validation.run_benchmark --backend mediapipe
    python -m validation.run_benchmark --backend both

The subject split is fixed: subject10 + subject11 are the tune set (2 subjects),
the remaining 8 are the held-out test set. The tune subjects are chosen to be the
first two alphanumerically — they are NEVER used to report accuracy, only to fit
the global convention (sign + offset). The test subjects are touched exactly once.
"""

from __future__ import annotations

import argparse
import json
import os

from .adapter import DataLayout
from .benchmark_real import run_from_trials
from .resolve_trials import resolve_all_trials

ROOT = "C:/Users/sagar/opencap_data/LabValidation_withVideos"
TUNE_SUBJECTS = ["subject10", "subject11"]   # fixed, never changes
OUT_DIR = "C:/Users/sagar/LANDR/validation/results"
CACHE_DIR = "C:/Users/sagar/LANDR/validation/pose_cache"

BANNER = """
================================================
  LANDR Real-Data Accuracy Benchmark
  Dataset : OpenCap LabValidation (Apache 2.0)
  Protocol: subject-split, tune->freeze->test
================================================"""


def run(backend: str = "rtmpose") -> dict:
    print(BANNER)
    print(f"\nBackend  : {backend}")
    print(f"Tune set : {TUNE_SUBJECTS}  (convention fit only, NOT reported)")
    print(f"Test set : all other subjects  (reported accuracy)\n")

    layout = DataLayout(root=ROOT)
    print(f"Pose cache: {CACHE_DIR}")
    print("Step 1/3  Resolving trials and running pose estimation...")
    trials = resolve_all_trials(ROOT, layout, backend=backend, verbose=True, cache_dir=CACHE_DIR)
    print(f"\n  {len(trials)} trial-sides collected")

    print("\nStep 2/3  Fitting convention on tune subjects...")
    report = run_from_trials(trials, tune_subjects=TUNE_SUBJECTS)
    for metric, conv in report.conventions.items():
        print(f"  {metric}: sign={conv.sign:+.0f}, offset={conv.offset:+.2f} deg")

    print(f"\nStep 3/3  Scoring {len(report.test_subjects)} held-out test subjects...")
    summary = report.summary()

    print("\n" + "=" * 54)
    print("RESULTS (held-out test subjects only)")
    print("=" * 54)
    for metric, vals in summary["per_metric"].items():
        print(f"\n  {metric.upper()}")
        print(f"    naive RMSE   : {vals['naive_rmse_deg']} deg")
        print(f"    improved RMSE: {vals['improved_rmse_deg']} deg")
        print(f"    reduction    : {vals['reduction_pct']}%")
        print(f"    worst trial  : {vals['worst_improved_deg']} deg")
        print(f"    n trial-sides: {vals['n']}")
    print("=" * 54)
    print(f"\nTest subjects: {report.test_subjects}")
    print(f"Tune subjects (not in results): {report.tune_subjects}")

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"results_{backend}.json")
    report.to_json(out_path)
    print(f"\nFull results saved to: {out_path}")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", default="rtmpose",
                        choices=["rtmpose"])
    args = parser.parse_args()

    run(backend=args.backend)


if __name__ == "__main__":
    main()
