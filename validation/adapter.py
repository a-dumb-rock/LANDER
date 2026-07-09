"""Map the OpenCap ``LabValidation_withVideos`` folder tree to what the benchmark
needs, and turn mocap markers into joint centres in LANDR's coordinate convention.

⚠️  THIS IS THE ONE MODULE TO FINALISE ONCE THE REAL DATA IS UNZIPPED.
    Everything else (readers, alignment, RMSE, subject split, self-test) is data-
    layout-independent and already tested. Run ``discover()`` on the unzipped root
    to print the real subject/trial/file/marker/column names, then adjust the
    candidate lists and the axis map below to match. Nothing here is guessed-and-
    hidden: the scanner surfaces exactly what to change.

OpenCap lab-frame convention (documented): Y = up, X = anterior, Z = right(lateral).
LANDR convention: x = medio-lateral, y = up, z = anterior-posterior. So the axis
map used below is  LANDR(x,y,z) = mocap(Z, Y, X).  Verify against the real .trc.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

import numpy as np

from .opensim_io import TrcData, read_trc, read_mot, MotData


# --------------------------------------------------------------------------- #
# Camera calibration loader
# --------------------------------------------------------------------------- #
def load_camera_calib(root: str, subject: str, camera: str) -> dict:
    """Load intrinsics + extrinsics for one camera/subject.

    Returns dict with:
      K  : (3,3) intrinsic matrix
      R  : (3,3) rotation  (world -> camera)
      t  : (3,)  translation in mm (world -> camera)
      dist: (5,) distortion coefficients
    """
    import pickle
    path = os.path.join(
        root, subject, "VideoData", "Session0", camera,
        "cameraIntrinsicsExtrinsics.pickle",
    )
    with open(path, "rb") as f:
        d = pickle.load(f)
    return {
        "K":    np.array(d["intrinsicMat"], float),
        "R":    np.array(d["rotation"],     float),
        "t":    np.array(d["translation"],  float).flatten(),
        "dist": np.array(d["distortion"],   float).flatten(),
    }


# --------------------------------------------------------------------------- #
# Configuration — candidate names & axis map (EDIT AFTER `discover()`)
# --------------------------------------------------------------------------- #
@dataclass
class DataLayout:
    root: str

    # Drop-jump trial name substring (case-insensitive match against folder name).
    dropjump_keys: tuple[str, ...] = ("DJ",)

    # Confirmed from camera extrinsics (optical-axis analysis):
    #   Cam2: optical_axis z≈1.0  → faces subject front-on → FRONTAL plane → valgus
    #   Cam0: optical_axis x≈0.91 → lateral view          → SAGITTAL plane → flexion
    front_camera: str = "Cam2"
    side_camera: str = "Cam0"

    # Confirmed real marker names from .trc files (51 markers, units=mm).
    markers: dict = field(default_factory=lambda: {
        "left": {
            "knee_lat":  ["L_knee"],
            "knee_med":  [],               # single knee marker — use as-is
            "ankle_lat": ["L_ankle"],
            "ankle_med": [],
            "hip":       ["L_HJC", "L_HJC_reg"],
        },
        "right": {
            "knee_lat":  ["r_knee"],
            "knee_med":  [],
            "ankle_lat": ["r_ankle"],
            "ankle_med": [],
            "hip":       ["R_HJC", "R_HJC_reg"],
        },
    })

    # OpenCap lab frame: X=lateral(right+), Y=up, Z=anterior.
    # LANDR convention:  x=medio-lateral, y=up, z=anterior-posterior.
    # Mapping: LANDR(x,y,z) = lab(X, Y, Z) → identity (0,1,2).
    axis_map: tuple[int, int, int] = (0, 1, 2)


# --------------------------------------------------------------------------- #
# Discovery — run this on the real unzipped root to finalise the config
# --------------------------------------------------------------------------- #
def discover(root: str, max_items: int = 8) -> str:
    """Walk the dataset and summarise subjects, trials, videos, .mot/.trc files.

    Returns a printable report; call this first thing after unzipping.
    """
    lines = [f"# OpenCap discovery under: {root}", ""]
    if not os.path.isdir(root):
        return f"NOT A DIRECTORY: {root}"

    subjects = sorted(
        d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))
    )
    lines.append(f"subjects ({len(subjects)}): {subjects[:max_items]}")

    def sample_ext(base: str, ext: str, cap: int = 6) -> list[str]:
        hits: list[str] = []
        for dp, _dn, fn in os.walk(base):
            for f in fn:
                if f.lower().endswith(ext):
                    hits.append(os.path.relpath(os.path.join(dp, f), base))
                    if len(hits) >= cap:
                        return hits
        return hits

    for subj in subjects[:2]:
        base = os.path.join(root, subj)
        lines.append(f"\n## {subj}")
        lines.append(f"  .mov : {sample_ext(base, '.mov')}")
        lines.append(f"  .mp4 : {sample_ext(base, '.mp4')}")
        lines.append(f"  .mot : {sample_ext(base, '.mot')}")
        lines.append(f"  .trc : {sample_ext(base, '.trc')}")
        # Peek at one .trc's marker names and one .mot's columns.
        trcs = sample_ext(base, ".trc", cap=1)
        if trcs:
            try:
                trc = read_trc(os.path.join(base, trcs[0]))
                lines.append(f"  markers[{len(trc.marker_names)}]: {trc.marker_names[:20]}")
                lines.append(f"  units: {trc.units}")
            except Exception as e:  # pragma: no cover
                lines.append(f"  (trc read failed: {e})")
        mots = sample_ext(base, ".mot", cap=1)
        if mots:
            try:
                mot = read_mot(os.path.join(base, mots[0]))
                lines.append(f"  mot columns: {mot.columns[:20]}")
            except Exception as e:  # pragma: no cover
                lines.append(f"  (mot read failed: {e})")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Marker -> joint-centre resolution (in LANDR convention)
# --------------------------------------------------------------------------- #
def _remap_axes(pts: np.ndarray, axis_map: tuple[int, int, int]) -> np.ndarray:
    """Reorder xyz columns of a (T,3) array per the lab->LANDR axis map."""
    i, j, k = axis_map
    return np.stack([pts[:, i], pts[:, j], pts[:, k]], axis=1)


def _center(trc: TrcData, names_lat: list[str], names_med: list[str] | None) -> np.ndarray:
    """Joint centre = midpoint of lateral+medial markers (or lateral alone)."""
    lat = trc.first_present(names_lat)
    if lat is None:
        raise KeyError(f"none of {names_lat} present in {trc.marker_names}")
    p = trc.marker(lat)
    if names_med:
        med = trc.first_present(names_med)
        if med is not None:
            p = 0.5 * (p + trc.marker(med))
    return p


def joint_centers(trc: TrcData, side: str, layout: DataLayout):
    """Return (time, hip, knee, ankle) as (T,3) arrays in LANDR convention.

    Positions are converted to metres if the file is in mm (angles are scale-
    invariant, but we normalise for cleanliness).
    """
    m = layout.markers[side]
    knee = _center(trc, m["knee_lat"], m.get("knee_med"))
    ankle = _center(trc, m["ankle_lat"], m.get("ankle_med"))
    hip = _center(trc, m["hip"], None)

    scale = 0.001 if trc.units.lower() == "mm" else 1.0
    hip, knee, ankle = hip * scale, knee * scale, ankle * scale

    am = layout.axis_map
    hip, knee, ankle = (_remap_axes(hip, am), _remap_axes(knee, am), _remap_axes(ankle, am))
    return trc.time.astype(float), hip, knee, ankle
