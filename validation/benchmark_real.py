"""Real-data accuracy benchmark with a leakage-proof subject split.

Protocol (this is the part that makes the number trustworthy):

  1. Split by SUBJECT into a small *tune* set and a held-out *test* set. No subject
     appears in both.
  2. On the tune set only, fit the global convention (one sign + one offset per
     metric) that reconciles LANDR's angle definition with the ground truth.
  3. Freeze it. Run once on the test set. Report naive vs improved RMSE there.

The alignment allows only a single global time lag per clip (video/mocap clocks
differ) — never per-frame warping. See ``align.py`` for why.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

import numpy as np

from .align import Convention, align_series, fit_convention, rmse


# --------------------------------------------------------------------------- #
# Intermediate representation (decouples the science from the file walking)
# --------------------------------------------------------------------------- #
@dataclass
class TrialAngles:
    """Everything needed to score one (subject, trial, metric, side)."""

    subject: str
    trial: str
    metric: str          # 'flexion' | 'valgus'
    side: str            # 'left' | 'right'
    fps: float
    t_pred: np.ndarray
    y_naive: np.ndarray
    y_improved: np.ndarray
    t_gt: np.ndarray
    y_gt: np.ndarray


def _concat_for_convention(trials: list[TrialAngles], metric: str) -> tuple[np.ndarray, np.ndarray]:
    """Pool tune-split IMPROVED predictions vs GT (roughly aligned) to fit sign+offset.

    We use a coarse resample to a common length per trial before pooling; the
    convention is only a sign+offset, so exact alignment is unnecessary here.
    """
    preds, gts = [], []
    for tr in trials:
        if tr.metric != metric:
            continue
        n = min(len(tr.y_improved), len(tr.y_gt))
        if n < 3:
            continue
        # coarse index-resample GT onto pred length for a pooled sign/offset fit
        gt_rs = np.interp(
            np.linspace(0, 1, len(tr.y_improved)),
            np.linspace(0, 1, len(tr.y_gt)),
            tr.y_gt,
        )
        preds.append(tr.y_improved)
        gts.append(gt_rs)
    if not preds:
        return np.array([]), np.array([])
    return np.concatenate(preds), np.concatenate(gts)


def fit_conventions(tune_trials: list[TrialAngles]) -> dict[str, Convention]:
    """Fit one Convention per metric on the tune split only."""
    conventions: dict[str, Convention] = {}
    for metric in ("flexion", "valgus"):
        p, g = _concat_for_convention(tune_trials, metric)
        conventions[metric] = fit_convention(p, g) if p.size else Convention()
    return conventions


# --------------------------------------------------------------------------- #
# Scoring
# --------------------------------------------------------------------------- #
@dataclass
class TrialScore:
    subject: str
    trial: str
    metric: str
    side: str
    naive_rmse: float
    improved_rmse: float
    lag: int


def score_trial(tr: TrialAngles, convention: Convention, ref_fps: float = 60.0) -> TrialScore:
    """Align and score one trial for both naive and improved predictions.

    The convention is applied to BOTH naive and improved (same definition fix),
    and the lag is found independently for each (they may jitter differently).
    """
    a_naive = align_series(tr.t_pred, tr.y_naive, tr.t_gt, tr.y_gt,
                           convention=convention, ref_fps=ref_fps)
    a_imp = align_series(tr.t_pred, tr.y_improved, tr.t_gt, tr.y_gt,
                         convention=convention, ref_fps=ref_fps)
    return TrialScore(
        subject=tr.subject, trial=tr.trial, metric=tr.metric, side=tr.side,
        naive_rmse=rmse(a_naive.pred, a_naive.gt),
        improved_rmse=rmse(a_imp.pred, a_imp.gt),
        lag=a_imp.lag,
    )


@dataclass
class BenchmarkReport:
    tune_subjects: list[str]
    test_subjects: list[str]
    conventions: dict[str, Convention]
    scores: list[TrialScore] = field(default_factory=list)

    def summary(self) -> dict:
        out: dict = {
            "tune_subjects": self.tune_subjects,
            "test_subjects": self.test_subjects,
            "conventions": {k: {"sign": v.sign, "offset": round(v.offset, 3)}
                            for k, v in self.conventions.items()},
            "per_metric": {},
            "n_trials": len(self.scores),
        }
        for metric in ("flexion", "valgus"):
            rows = [s for s in self.scores if s.metric == metric]
            if not rows:
                continue
            naive = float(np.mean([s.naive_rmse for s in rows]))
            imp = float(np.mean([s.improved_rmse for s in rows]))
            reduction = 100.0 * (naive - imp) / naive if naive > 1e-9 else 0.0
            out["per_metric"][metric] = {
                "n": len(rows),
                "naive_rmse_deg": round(naive, 2),
                "improved_rmse_deg": round(imp, 2),
                "reduction_pct": round(reduction, 1),
                "worst_improved_deg": round(max(s.improved_rmse for s in rows), 2),
            }
        return out

    def to_json(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(self.summary(), fh, indent=2)


def run_from_trials(
    all_trials: list[TrialAngles],
    tune_subjects: list[str],
    ref_fps: float = 60.0,
) -> BenchmarkReport:
    """Core benchmark: fit conventions on tune subjects, score on the rest.

    This is fully unit-testable with synthetic ``TrialAngles`` (see selftest.py) —
    no video, pose backend, or download required.
    """
    tune_set = set(tune_subjects)
    tune = [t for t in all_trials if t.subject in tune_set]
    test = [t for t in all_trials if t.subject not in tune_set]
    test_subjects = sorted({t.subject for t in test})

    conventions = fit_conventions(tune)
    scores = [score_trial(t, conventions[t.metric], ref_fps=ref_fps) for t in test]
    return BenchmarkReport(
        tune_subjects=sorted(tune_set),
        test_subjects=test_subjects,
        conventions=conventions,
        scores=scores,
    )
