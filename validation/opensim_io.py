"""Readers for the two OpenSim/mocap file formats in the OpenCap dataset.

These formats are stable, decades-old standards, so these parsers are safe to
build and test *before* the real 19 GB download lands.

  * ``.mot`` / ``.sto`` — OpenSim motion/storage: a metadata header terminated by
    an ``endheader`` line, then a tab-separated column-name row, then numeric rows.
    We use it for the ground-truth **knee flexion** angle (``knee_angle_r/l``).

  * ``.trc`` — marker trajectories (Motion Analysis format): fixed 5-line header,
    then per-frame 3D positions for each marker. We use it to derive a ground-truth
    frontal-plane **valgus** proxy from hip/knee/ankle markers, computed with the
    *same* geometry LANDR uses so the comparison is apples-to-apples.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


# --------------------------------------------------------------------------- #
# .mot / .sto  (OpenSim inverse-kinematics joint angles)
# --------------------------------------------------------------------------- #
@dataclass
class MotData:
    """Parsed OpenSim motion file."""

    columns: list[str]          # column names, first is 'time'
    data: np.ndarray            # shape (T, n_columns), float
    in_degrees: bool            # whether angular columns are already in degrees

    def time(self) -> np.ndarray:
        return self.data[:, 0]

    def column(self, name: str) -> np.ndarray:
        """Return one column by (case-insensitive) name."""
        low = [c.lower() for c in self.columns]
        try:
            j = low.index(name.lower())
        except ValueError as exc:  # pragma: no cover - guard for bad names
            raise KeyError(
                f"column {name!r} not in {self.columns}"
            ) from exc
        return self.data[:, j]

    def has(self, name: str) -> bool:
        return name.lower() in (c.lower() for c in self.columns)


def read_mot(path: str) -> MotData:
    """Parse an OpenSim ``.mot``/``.sto`` file.

    The header is free-form ``key=value`` lines terminated by ``endheader``. We
    read ``inDegrees`` if present, then take the first non-empty line after the
    header as the tab-separated column names, and the rest as a numeric matrix.
    """
    in_degrees = True
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()

    # 1) find end of header
    header_end = None
    for i, ln in enumerate(lines):
        low = ln.strip().lower()
        if low.startswith("indegrees"):
            in_degrees = low.split("=")[-1].strip() == "yes"
        if low == "endheader":
            header_end = i
            break
    if header_end is None:
        # Some files have no explicit endheader; fall back to first line that
        # looks like a tab-separated column row containing 'time'.
        for i, ln in enumerate(lines):
            if "time" in ln.lower() and "\t" in ln:
                header_end = i - 1
                break
    if header_end is None:
        raise ValueError(f"{path}: could not locate header end")

    # 2) column names = first non-empty line after header
    idx = header_end + 1
    while idx < len(lines) and not lines[idx].strip():
        idx += 1
    columns = [c.strip() for c in lines[idx].split("\t") if c.strip() != ""]

    # 3) numeric data
    rows = []
    for ln in lines[idx + 1:]:
        if not ln.strip():
            continue
        parts = [p for p in ln.replace(",", " ").split() if p != ""]
        if len(parts) < len(columns):
            continue
        rows.append([float(p) for p in parts[: len(columns)]])
    if not rows:
        raise ValueError(f"{path}: no numeric rows parsed")
    return MotData(columns=columns, data=np.asarray(rows, float), in_degrees=in_degrees)


# --------------------------------------------------------------------------- #
# .trc  (3D marker trajectories)
# --------------------------------------------------------------------------- #
@dataclass
class TrcData:
    """Parsed marker-trajectory file."""

    marker_names: list[str]
    time: np.ndarray                       # shape (T,)
    positions: np.ndarray                  # shape (T, M, 3)
    units: str                             # 'mm' or 'm'

    def marker(self, name: str) -> np.ndarray:
        """Return the (T, 3) trajectory of one marker (exact name match)."""
        j = self.marker_names.index(name)
        return self.positions[:, j, :]

    def first_present(self, candidates: list[str]) -> str | None:
        """Return the first marker name in ``candidates`` that exists, else None."""
        present = set(self.marker_names)
        for c in candidates:
            if c in present:
                return c
        return None


def read_trc(path: str) -> TrcData:
    """Parse a ``.trc`` marker file.

    Layout (tab-separated):
        line1  PathFileType ... filename
        line2  field names   (DataRate CameraRate NumFrames NumMarkers Units ...)
        line3  field values
        line4  Frame# Time <MarkerA> <> <> <MarkerB> ...   (name every 3 cols)
        line5  '' '' X1 Y1 Z1 X2 Y2 Z2 ...
        line6+ data rows: frame time x y z x y z ...
    """
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    if len(lines) < 6:
        raise ValueError(f"{path}: too short to be a .trc file")

    field_names = lines[1].split("\t")
    field_vals = lines[2].split("\t")
    meta = {k.strip(): v.strip() for k, v in zip(field_names, field_vals)}
    units = meta.get("Units", "mm").strip() or "mm"

    # Marker names: row 4, columns after 'Frame#' and 'Time', one name per 3 cols.
    name_cells = lines[3].split("\t")
    marker_names = [c.strip() for c in name_cells[2:] if c.strip() != ""]

    # Data begins after the two header rows (4 and 5); skip blanks.
    data_rows = []
    for ln in lines[5:]:
        if not ln.strip():
            continue
        parts = [p for p in ln.split("\t")]
        # Some exporters use spaces; normalise.
        if len(parts) < 2:
            parts = ln.split()
        vals = [float(p) if p.strip() not in ("", None) else np.nan
                for p in parts if p.strip() != ""]
        if len(vals) < 2 + 3:  # need at least frame,time + one xyz
            continue
        data_rows.append(vals)

    if not data_rows:
        raise ValueError(f"{path}: no marker data parsed")

    width = 2 + 3 * len(marker_names)
    mat = np.full((len(data_rows), width), np.nan)
    for i, row in enumerate(data_rows):
        n = min(len(row), width)
        mat[i, :n] = row[:n]

    time = mat[:, 1]
    coords = mat[:, 2:2 + 3 * len(marker_names)]
    positions = coords.reshape(len(data_rows), len(marker_names), 3)
    return TrcData(marker_names=marker_names, time=time, positions=positions, units=units)
