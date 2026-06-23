"""LANDR command-line interface.

Examples
--------
    python -m landr.cli demo                       # synthetic high-risk landing
    python -m landr.cli demo --quality good        # synthetic low-risk landing
    python -m landr.cli analyze jump.mp4 --plot p.png --out r.json
    python -m landr.cli fatigue                     # fresh-vs-fatigued comparison (Pillar 2)
    python -m landr.cli fatigue --plot f.png        # + overlay plot
    python -m landr.cli benchmark                   # accuracy gain on synthetic data (Pillar 1)
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from . import __version__
from .pipeline import analyze, analyze_sequence
from .synthetic import synthetic_jump


def _load_env() -> None:
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except Exception:
        pass


def _print_summary(result: Any) -> None:
    r = result.risk
    print("\n" + "=" * 60)
    print(f"  LANDR result — risk: {r.category.upper()}  "
          f"(score {r.score_0_100}/100, LESS total {r.less_total})")
    print("=" * 60)
    print("\nFlagged patterns:")
    errs = result.less.errors()
    if errs:
        for e in errs:
            print(f"  • {e.description}  [{e.detail}]")
    else:
        print("  • none")
    print(f"\nReport provider: {result.report_provider}\n")
    print(result.report)
    print()


def _save(result: Any, out: str | None, plot: str | None) -> None:
    if out:
        with open(out, "w") as fh:
            json.dump(result.as_dict(), fh, indent=2)
        print(f"[saved] full result -> {out}")
    if plot:
        from .viz import plot_analysis
        plot_analysis(result, plot)
        print(f"[saved] angle plot   -> {plot}")


# --------------------------------------------------------------------------- #
# Subcommand handlers
# --------------------------------------------------------------------------- #
def _cmd_demo(args) -> int:
    seq = synthetic_jump(quality=args.quality)
    athlete = {"name": args.name} if args.name else None
    result = analyze_sequence(seq, athlete=athlete,
                              report_provider=args.provider, report_model=args.model)
    _print_summary(result)
    _save(result, args.out, args.plot)
    return 0


_ACCURACY_TO_SIZE = {"fast": "lite", "balanced": "full", "max": "heavy"}


def _resolve_size(args) -> str:
    """--accuracy preset wins if set; else fall back to --model-size."""
    if getattr(args, "accuracy", None):
        return _ACCURACY_TO_SIZE[args.accuracy]
    return args.model_size


def _cmd_analyze(args) -> int:
    athlete = {"name": args.name} if args.name else None
    try:
        result = analyze(args.video, athlete=athlete,
                         report_provider=args.provider, report_model=args.model,
                         model_size=_resolve_size(args), backend=args.backend,
                         refine=not args.no_refine)
    except ImportError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 2
    except (FileNotFoundError, ValueError) as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1
    _print_summary(result)
    _save(result, args.out, args.plot)
    return 0


def _cmd_analyze2(args) -> int:
    """Two-view (front + side) analysis — best single-camera accuracy."""
    from .multiview import analyze_two_view
    athlete = {"name": args.name} if args.name else None
    try:
        result = analyze_two_view(
            args.front, args.side, athlete=athlete,
            report_provider=args.provider, report_model=args.model,
            model_size=_resolve_size(args), backend=args.backend,
            refine=not args.no_refine)
    except ImportError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 2
    except (FileNotFoundError, ValueError) as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1
    print("[two-view] valgus from FRONT, knee/trunk flexion from SIDE")
    _print_summary(result)
    _save(result, args.out, args.plot)
    return 0


def _cmd_fatigue(args) -> int:
    """Compare a fresh vs a fatigued session (synthetic by default)."""
    from .fatigue import compare, fatigue_report

    if args.fresh and args.fatigued:
        with open(args.fresh) as fh:
            fresh = _result_from_json(json.load(fh))
        with open(args.fatigued) as fh:
            fatigued = _result_from_json(json.load(fh))
    else:
        fresh_seq = synthetic_jump(quality=args.quality, fatigue=0.0, seed=1)
        fatigued_seq = synthetic_jump(quality=args.quality, fatigue=args.level, seed=1)
        fresh = analyze_sequence(fresh_seq)
        fatigued = analyze_sequence(fatigued_seq)

    cmp = compare(fresh, fatigued)
    print("\n" + "=" * 60)
    print(f"  FATIGUE-VULNERABILITY: {cmp.category.upper()}  "
          f"(score {cmp.vulnerability_score}/100)")
    print("=" * 60)
    print("\nFresh vs fatigued change:")
    for k, v in cmp.deltas.items():
        print(f"  • {k}: {v:+}")
    print()
    print(fatigue_report(cmp, name=args.name))
    print()

    if args.out:
        with open(args.out, "w") as fh:
            json.dump(cmp.as_dict(), fh, indent=2)
        print(f"[saved] fatigue comparison -> {args.out}")
    if args.plot:
        from .viz import plot_fatigue
        plot_fatigue(fresh, fatigued, args.plot)
        print(f"[saved] fresh-vs-fatigued plot -> {args.plot}")
    return 0


def _cmd_benchmark(args) -> int:
    """Quantify the single-camera accuracy gain from the corrections."""
    from .accuracy import run_accuracy_benchmark

    res = run_accuracy_benchmark(noise_std=args.noise, seed=args.seed)
    print("\n" + "=" * 64)
    print(f"  ACCURACY BENCHMARK (simulated pose noise std={res['noise_std']})")
    print("=" * 64)
    print(f"\n  {'metric':<10} {'naive RMSE':>12} {'improved':>12} {'reduction':>12}")
    print("  " + "-" * 48)
    for which in ("valgus", "flexion"):
        r = res[which]
        print(f"  {which:<10} {r['naive_rmse_deg']:>10}°  {r['improved_rmse_deg']:>10}°  "
              f"{r['reduction_pct']:>10}%")
    print("\n  (temporal smoothing + limb-length constraint vs naive per-frame pose)")
    print("  NOTE: simulation; real validation needs marker-based motion capture.\n")
    if args.out:
        with open(args.out, "w") as fh:
            json.dump(res, fh, indent=2)
        print(f"[saved] benchmark -> {args.out}")
    return 0


def _result_from_json(d: dict) -> Any:
    """Minimal reconstruction of an AnalysisResult from saved JSON (for fatigue)."""
    from .types import AnalysisResult, LandingEvents, LessItem, LessResult, RiskResult
    less = LessResult(
        items=[LessItem(**it) for it in d["less"]["items"]],
        total=d["less"]["total"],
    )
    return AnalysisResult(
        metrics=d["metrics"],
        events=LandingEvents(**d["events"]),
        less=less,
        risk=RiskResult(**d["risk"]),
        report=d.get("report", ""),
        report_provider=d.get("report_provider", "mock"),
        meta=d.get("meta", {}),
    )


def main(argv: list[str] | None = None) -> int:
    _load_env()
    parser = argparse.ArgumentParser(
        prog="landr", description="Fatigue-aware ACL injury-risk screening from a single video.")
    parser.add_argument("--version", action="version", version=f"LANDR {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--out", help="Write result JSON to this path.")
    common.add_argument("--plot", nargs="?", const="landr_plot.png",
                        help="Save a plot (default landr_plot.png).")
    common.add_argument("--provider", default="mock", choices=["mock", "openai", "gemini"])
    common.add_argument("--model", default=None, help="Override VLM model name.")
    common.add_argument("--name", default=None, help="Athlete name for the report.")

    p_demo = sub.add_parser("demo", parents=[common], help="Run on a synthetic jump.")
    p_demo.add_argument("--quality", default="poor", choices=["good", "poor"])

    p_an = sub.add_parser("analyze", parents=[common], help="Run on a real video.")
    p_an.add_argument("video", help="Path to the jump-landing video.")
    p_an.add_argument("--accuracy", choices=["fast", "balanced", "max"],
                      help="Preset: fast=lite, balanced=full, max=heavy pose model.")
    p_an.add_argument("--model-size", default="full", choices=["lite", "full", "heavy"],
                      help="Pose model (overridden by --accuracy if set).")
    p_an.add_argument("--backend", default="mediapipe", choices=["mediapipe", "rtmpose"],
                      help="rtmpose = highest accuracy (pip install rtmlib onnxruntime).")
    p_an.add_argument("--no-refine", action="store_true",
                      help="Disable the accuracy pass (temporal + anatomical).")

    p_a2 = sub.add_parser("analyze2", parents=[common],
                          help="Two-view (front + side) analysis — best accuracy.")
    p_a2.add_argument("front", help="Front-view jump video (for valgus).")
    p_a2.add_argument("side", help="Side-view jump video (for knee/trunk flexion).")
    p_a2.add_argument("--accuracy", choices=["fast", "balanced", "max"],
                      help="Preset: fast=lite, balanced=full, max=heavy pose model.")
    p_a2.add_argument("--model-size", default="full", choices=["lite", "full", "heavy"])
    p_a2.add_argument("--backend", default="mediapipe", choices=["mediapipe", "rtmpose"])
    p_a2.add_argument("--no-refine", action="store_true")

    p_fat = sub.add_parser("fatigue", parents=[common],
                           help="Fresh-vs-fatigued comparison (Pillar 2).")
    p_fat.add_argument("--quality", default="good", choices=["good", "poor"])
    p_fat.add_argument("--level", type=float, default=0.8,
                       help="Synthetic fatigue level 0-1 (default 0.8).")
    p_fat.add_argument("--fresh", default=None, help="JSON from a fresh `analyze --out`.")
    p_fat.add_argument("--fatigued", default=None, help="JSON from a fatigued `analyze --out`.")

    p_bench = sub.add_parser("benchmark", help="Accuracy gain on synthetic data (Pillar 1).")
    p_bench.add_argument("--noise", type=float, default=0.055, help="Simulated pose noise std.")
    p_bench.add_argument("--seed", type=int, default=0)
    p_bench.add_argument("--out", help="Write benchmark JSON to this path.")

    args = parser.parse_args(argv)
    return {
        "demo": _cmd_demo,
        "analyze": _cmd_analyze,
        "analyze2": _cmd_analyze2,
        "fatigue": _cmd_fatigue,
        "benchmark": _cmd_benchmark,
    }[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
