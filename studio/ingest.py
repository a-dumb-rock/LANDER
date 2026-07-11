"""LANDR Studio — real video ingestion and keypoints file I/O.

This module bridges real-world video capture to the triangulation pipeline.
Three modes of operation:

1. **Live detection** (needs rtmlib + opencv):
       CaptureView(camera=cam, video="cam0.mp4")
   RTMPoseDetector.run() handles this path (see detector.py).

2. **Precomputed keypoints from file** (numpy-only):
       load_keypoints("cam0.npy")  ->  (kp, conf)   # fast, no GPU needed
   Useful when detection has already been run, or on deployment machines
   without rtmlib.

3. **CLI** (processes videos or keypoint files into a full analysis):
       python -m studio.ingest --videos cam0.mp4 cam1.mp4 \\
                                --rig rig.json --athlete "Alex Rivera"

Keypoint files are .npy bundles storing {"keypoints": ..., "confidences": ...}
via np.save with allow_pickle=True, or .json arrays.

File format (.npy):
    np.save(path, {"keypoints": (T,J,2), "confidences": (T,J)})
    k = np.load(path, allow_pickle=True).item()

File format (.json):
    {"keypoints": [[[u,v],...], ...], "confidences": [[c,...], ...]}
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np

from landr import config


# ---------------------------------------------------------------------------
# File I/O helpers
# ---------------------------------------------------------------------------

def save_keypoints(path: str | Path, keypoints: np.ndarray, confidences: np.ndarray) -> None:
    """Save per-view keypoints to a .npy or .json file.

    keypoints  : (T, J, 2) pixel coordinates
    confidences: (T, J)    scores in [0,1]
    """
    path = Path(path)
    kp = np.asarray(keypoints, float)
    cf = np.asarray(confidences, float)
    if path.suffix == ".json":
        with path.open("w") as f:
            json.dump({"keypoints": kp.tolist(), "confidences": cf.tolist()}, f)
    else:
        np.save(path, {"keypoints": kp, "confidences": cf})


def load_keypoints(path: str | Path) -> tuple[np.ndarray, np.ndarray]:
    """Load keypoints from a .npy or .json file saved by :func:`save_keypoints`.

    Returns (keypoints (T,J,2), confidences (T,J)).
    """
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(path)
    if path.suffix == ".json":
        data: dict[str, Any] = json.loads(path.read_text())
    else:
        data = np.load(path, allow_pickle=True).item()
    kp = np.asarray(data["keypoints"], float)
    cf = np.asarray(data["confidences"], float)
    return kp, cf


# ---------------------------------------------------------------------------
# CameraRig I/O
# ---------------------------------------------------------------------------

def load_rig(path: str | Path):
    """Load a CameraRig from a JSON file produced by ``rig.to_dict()``."""
    from .calibration import CameraRig
    with open(path) as f:
        return CameraRig.from_dict(json.load(f))


def save_rig(path: str | Path, rig) -> None:
    """Save a CameraRig to JSON."""
    with open(path, "w") as f:
        json.dump(rig.to_dict(), f, indent=2)


# ---------------------------------------------------------------------------
# Detection from video files (rtmlib / opencv path)
# ---------------------------------------------------------------------------

def detect_views(
    video_paths: list[str],
    cameras,
    mode: str = "performance",
    save_keypoints_dir: str | None = None,
) -> list:
    """Run RTMPose on each video and return CaptureView objects.

    If *save_keypoints_dir* is given, detected keypoints are saved as .npy
    files in that directory (named cam0.npy, cam1.npy, …) so the analysis
    can be reproduced without re-running detection.
    """
    from .detector import RTMPoseDetector
    from .pipeline import CaptureView

    detector = RTMPoseDetector(mode=mode)
    views = []
    for i, (video, cam) in enumerate(zip(video_paths, cameras)):
        print(f"  detecting cam{i}: {video} …", flush=True)
        kp, cf, fps = detector.run(video)
        if save_keypoints_dir is not None:
            out = Path(save_keypoints_dir) / f"cam{i}.npy"
            save_keypoints(out, kp, cf)
            print(f"    saved -> {out}")
        views.append(CaptureView(camera=cam, keypoints=kp, confidences=cf))
    return views


def load_views(
    keypoint_paths: list[str],
    cameras,
) -> list:
    """Build CaptureView objects from pre-saved keypoint files."""
    from .pipeline import CaptureView
    views = []
    for path, cam in zip(keypoint_paths, cameras):
        kp, cf = load_keypoints(path)
        views.append(CaptureView(camera=cam, keypoints=kp, confidences=cf))
    return views


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python -m studio.ingest",
        description="Analyse a multi-view landing capture from video files or precomputed keypoints.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples
--------
# From videos (requires rtmlib):
  python -m studio.ingest --videos front.mp4 side.mp4 left.mp4 right.mp4 \\
                           --rig rig.json --athlete "Alex Rivera"

# From precomputed keypoints (faster, no GPU needed):
  python -m studio.ingest --keypoints cam0.npy cam1.npy cam2.npy cam3.npy \\
                           --rig rig.json --athlete "Alex Rivera"

# Run detection AND save keypoints for later reuse:
  python -m studio.ingest --videos *.mp4 --rig rig.json \\
                           --save-keypoints ./kp_cache/

# Save the full JSON report:
  python -m studio.ingest --keypoints *.npy --rig rig.json \\
                           --output report.json

# Print an HTML clinical report to stdout:
  python -m studio.ingest --keypoints *.npy --rig rig.json \\
                           --report-html > report.html
""",
    )
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--videos", nargs="+", metavar="VIDEO",
                     help="Video file for each camera (same order as rig cameras).")
    src.add_argument("--keypoints", nargs="+", metavar="KP_FILE",
                     help="Pre-saved .npy/.json keypoint file per camera.")

    p.add_argument("--rig", metavar="RIG_JSON", required=True,
                   help="Camera rig JSON file (produced by save_rig / CameraRig.to_dict()).")
    p.add_argument("--athlete", default="", metavar="NAME", help="Athlete display name.")
    p.add_argument("--output", "-o", metavar="OUT_JSON",
                   help="Write the full analysis JSON to this path.")
    p.add_argument("--report-html", action="store_true",
                   help="Print an HTML clinical report to stdout instead of JSON summary.")
    p.add_argument("--save-keypoints", metavar="DIR",
                   help="(--videos only) Save detected keypoints here for later reuse.")
    p.add_argument("--no-ransac", action="store_true",
                   help="Disable RANSAC outlier rejection in triangulation.")
    return p


def main(argv: list[str] | None = None) -> None:
    args = _build_parser().parse_args(argv)

    print("Loading rig …", flush=True)
    rig = load_rig(args.rig)
    n_cams = len(rig.cameras)

    sources = args.videos or args.keypoints
    if len(sources) != n_cams:
        print(
            f"Error: rig has {n_cams} cameras but {len(sources)} source(s) provided.",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.videos:
        if args.save_keypoints:
            Path(args.save_keypoints).mkdir(parents=True, exist_ok=True)
        views = detect_views(
            args.videos, rig.cameras,
            save_keypoints_dir=args.save_keypoints,
        )
    else:
        print("Loading keypoints …", flush=True)
        views = load_views(args.keypoints, rig.cameras)

    from .pipeline import analyze_capture

    print("Triangulating + analysing …", flush=True)
    result = analyze_capture(
        views, rig,
        athlete={"name": args.athlete} if args.athlete else {},
        robust=not args.no_ransac,
    )

    if args.report_html:
        from .report import render_report
        print(render_report(result, athlete_name=args.athlete or "Athlete"))
        return

    summary = result.as_dict()

    if args.output:
        with open(args.output, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"Report saved -> {args.output}")

    # Always print a compact terminal summary.
    risk = result.risk
    less = result.less
    metrics = result.metrics
    cat_color = {"low": "\033[92m", "moderate": "\033[93m", "high": "\033[91m"}.get(
        risk.category, ""
    )
    reset = "\033[0m"
    print()
    print(f"{'─'*52}")
    print(f"  Athlete : {args.athlete or '(unnamed)'}")
    print(f"  Risk    : {cat_color}{risk.category.upper()}{reset}  (score {risk.score_0_100:.0f}/100)")
    print(f"  LESS    : {less.total} error(s)")

    flex_ic = metrics.get("knee_flexion_ic_deg", {})
    flex_lp = metrics.get("knee_flexion_lp_deg", {})
    valgus  = metrics.get("peak_valgus_deg", {})
    asym    = metrics.get("asymmetry_index", 0.0)
    if isinstance(asym, dict):
        asym = max(asym.values()) if asym else 0.0

    def _avg(d):
        vals = list(d.values()) if isinstance(d, dict) else []
        return sum(vals) / len(vals) if vals else float("nan")

    print(f"  Flexion IC / LP : {_avg(flex_ic):.1f}° / {_avg(flex_lp):.1f}°")
    print(f"  Peak valgus     : {_avg(valgus):.1f}°")
    print(f"  Asymmetry       : {asym*100:.1f}%")
    print(f"{'─'*52}")

    if less.errors():
        print("  LESS errors:")
        for e in less.errors():
            print(f"    ✗  {e.description}")
    print()


if __name__ == "__main__":
    main()
