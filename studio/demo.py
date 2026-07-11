"""Ready-made demo captures that exercise the real Studio pipeline.

These build a synthetic athlete, project into a 4-camera rig, then run the *actual*
:func:`studio.pipeline.analyze_capture` (triangulate -> anatomical -> clinical
engine). So the dashboard's demo is not hand-typed numbers — it is the genuine
reconstruction of a known capture, off-axis to the cameras (``facing_deg``) to show
the geometry handling a realistic setup.
"""

from __future__ import annotations

from typing import Any

from landr.types import AnalysisResult

from .calibration import make_arc_rig
from .pipeline import CaptureView, analyze_capture
from .synthetic import make_landing_capture, project_to_views

# Two contrasting athletes. facing_deg puts them off the camera axis on purpose.
_PROFILES: dict[str, dict[str, Any]] = {
    "good": {
        "athlete": {"name": "A. Rivera", "sport": "Basketball", "id": "STU-014"},
        "params": dict(valgus_gain=1.5, asymmetry=0.08, trunk_lean_deg=24.0,
                       depth_scale=1.0, facing_deg=22.0),
    },
    "at_risk": {
        "athlete": {"name": "J. Okafor", "sport": "Soccer", "id": "STU-027"},
        "params": dict(valgus_gain=6.0, asymmetry=0.30, trunk_lean_deg=9.0,
                       depth_scale=0.62, facing_deg=22.0),
    },
}


def make_demo_result(profile: str = "good", pixel_noise: float = 0.6) -> AnalysisResult:
    """Run the full pipeline on a synthetic capture and return the analysis."""
    if profile not in _PROFILES:
        raise ValueError(f"unknown demo profile {profile!r}; choose {list(_PROFILES)}")
    spec = _PROFILES[profile]
    rig = make_arc_rig(n_cameras=4, radius=3.0, height=1.2, arc_deg=160.0)
    world = make_landing_capture(n_frames=90, fps=60.0, seed=1, **spec["params"])
    kp, conf = project_to_views(world, rig, pixel_noise=pixel_noise, seed=7)
    views = [
        CaptureView(camera=cam, keypoints=kp[i], confidences=conf[i])
        for i, cam in enumerate(rig.cameras)
    ]
    result = analyze_capture(views, rig, athlete=spec["athlete"])
    result.meta["demo_profile"] = profile
    result.meta["capture"] = {
        "trial": "Drop vertical jump",
        "facing_deg": spec["params"]["facing_deg"],
        "pixel_noise_px": pixel_noise,
    }
    # Embed the rig so the dashboard can forward it to a live WebSocket session.
    result.meta["rig"] = rig.to_dict()
    return result


if __name__ == "__main__":
    for prof in ("good", "at_risk"):
        r = make_demo_result(prof)
        m = r.metrics
        print(
            f"{prof:8s} | flex@IC {m['at_initial_contact']['knee_flexion_deg']:5.1f}  "
            f"peak valgus {max(abs(m['peak_valgus_deg']['left']), abs(m['peak_valgus_deg']['right'])):5.1f}  "
            f"asym {m['asymmetry_index']:.2f}  LESS {r.less.total}  "
            f"risk {r.risk.category} ({r.risk.score_0_100})"
        )
