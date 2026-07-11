"""LANDR Studio — printable clinical report generator.

Produces a self-contained, print-optimized HTML page for a single athlete's
analysis. Designed for A4/Letter printing: all colours switch to high-contrast
grayscale, the skeleton viewer and interactive controls are hidden, and the
clinical data (risk score, LESS checklist, key metrics, recommendations) are
laid out for easy reading and filing.

Usage (programmatic):
    from studio.report import render_report
    html = render_report(result, athlete_name="Alex Rivera", session_id="S24-001")

Usage (server):
    GET /report?profile=good
    GET /report?profile=at_risk
"""

from __future__ import annotations

import datetime
from typing import Any

from landr.types import AnalysisResult


# ---------------------------------------------------------------------------
# Recommendation library
# ---------------------------------------------------------------------------

_RECS: dict[str, str] = {
    "trunk_lean": (
        "Reduce trunk forward lean at initial contact through hip hinge drills and "
        "eccentric hamstring strengthening."
    ),
    "knee_valgus": (
        "Address knee valgus by strengthening hip abductors and external rotators. "
        "Incorporate landing technique feedback with real-time visual cueing."
    ),
    "knee_flexion_ic": (
        "Increase initial-contact knee flexion (target ≥30°) through plyometric "
        "progression and 'soft landing' coaching cues."
    ),
    "knee_flexion_lp": (
        "Increase landing depth (target ≥70° at lowest point) to distribute impact "
        "forces across a larger range of motion."
    ),
    "asymmetry": (
        "Address bilateral asymmetry (>15%) with single-leg strengthening protocols "
        "and limb-symmetry re-training before return to sport."
    ),
    "arm_swing": (
        "Train forward arm swing mechanics during landing to improve anterior "
        "balance and reduce compensatory trunk rotation."
    ),
    "general": (
        "Continue current training programme. No biomechanical risk factors were "
        "detected that require immediate intervention."
    ),
}


def _recommendations(result: AnalysisResult) -> list[str]:
    recs = []
    errors = {e.key for e in result.less.errors()}
    metrics = result.metrics

    if "knee_valgus" in errors or any(
        abs(v) > 10 for v in (metrics.get("peak_valgus_deg") or {}).values()
    ):
        recs.append(_RECS["knee_valgus"])
    if "trunk_lean" in errors:
        recs.append(_RECS["trunk_lean"])
    if "knee_flexion_ic" in errors or any(
        v < 30 for v in (metrics.get("knee_flexion_ic_deg") or {}).values()
    ):
        recs.append(_RECS["knee_flexion_ic"])
    if "knee_flexion_lp" in errors or any(
        v < 70 for v in (metrics.get("knee_flexion_lp_deg") or {}).values()
    ):
        recs.append(_RECS["knee_flexion_lp"])
    asym = metrics.get("asymmetry_index", 0.0)
    if isinstance(asym, dict):
        asym = max(asym.values(), default=0.0)
    if float(asym) > 0.15:
        recs.append(_RECS["asymmetry"])
    if "arm_swing" in errors:
        recs.append(_RECS["arm_swing"])

    if not recs:
        recs.append(_RECS["general"])
    return recs


# ---------------------------------------------------------------------------
# Metric formatting helpers
# ---------------------------------------------------------------------------

def _fmt_deg(v: Any, places: int = 1) -> str:
    try:
        return f"{float(v):.{places}f}°"
    except (TypeError, ValueError):
        return "—"


def _fmt_pct(v: Any, places: int = 1) -> str:
    try:
        return f"{float(v)*100:.{places}f}%"
    except (TypeError, ValueError):
        return "—"


def _bilateral(d: Any, fmt) -> str:
    if isinstance(d, dict):
        parts = [f"{k.title()}: {fmt(v)}" for k, v in d.items()]
        return " · ".join(parts) if parts else "—"
    try:
        return fmt(d)
    except Exception:
        return "—"


# ---------------------------------------------------------------------------
# HTML builder
# ---------------------------------------------------------------------------

_RISK_COLOR = {"low": "#16a34a", "moderate": "#d97706", "high": "#dc2626"}
_RISK_BG    = {"low": "#f0fdf4", "moderate": "#fffbeb", "high": "#fef2f2"}


def render_report(
    result: AnalysisResult,
    athlete_name: str = "Athlete",
    session_id: str = "",
    assessor: str = "",
    notes: str = "",
) -> str:
    """Return a self-contained HTML string suitable for printing or saving."""

    risk  = result.risk
    less  = result.less
    metrics = result.metrics
    events  = result.events
    meta    = result.meta

    risk_col = _RISK_COLOR.get(risk.category, "#374151")
    risk_bg  = _RISK_BG.get(risk.category, "#f9fafb")

    today    = datetime.date.today().strftime("%B %d, %Y")
    session_label = f"Session {session_id}" if session_id else "Assessment"

    flex_ic  = metrics.get("knee_flexion_ic_deg", {})
    flex_lp  = metrics.get("knee_flexion_lp_deg", {})
    valgus   = metrics.get("peak_valgus_deg", {})
    asym_raw = metrics.get("asymmetry_index", 0.0)
    if isinstance(asym_raw, dict):
        asym_raw = max(asym_raw.values(), default=0.0)
    asym_pct = float(asym_raw) * 100

    trunk    = metrics.get("trunk_lean_deg", None)
    product  = meta.get("product", "studio")
    n_views  = meta.get("n_views", "—")
    recon_conf = meta.get("reconstruction_confidence", None)

    # LESS table rows
    less_rows = ""
    for item in less.items:
        chk = "✗" if item.error else "✓"
        chk_color = "#dc2626" if item.error else "#16a34a"
        val_str = f" ({_fmt_deg(item.value)})" if item.value is not None else ""
        detail  = f"<span class='detail'>{item.detail}</span>" if item.detail else ""
        less_rows += f"""
        <tr class="{'err' if item.error else 'ok'}">
          <td class="chk" style="color:{chk_color}">{chk}</td>
          <td class="desc">{item.description}{val_str}{detail}</td>
        </tr>"""

    # Metric table rows
    def _row(label, val):
        return f"<tr><td class='ml'>{label}</td><td class='mv'>{val}</td></tr>"

    metric_rows = (
        _row("Knee Flexion @ Initial Contact",
             _bilateral(flex_ic, lambda v: _fmt_deg(v))) +
        _row("Knee Flexion @ Lowest Point",
             _bilateral(flex_lp, lambda v: _fmt_deg(v))) +
        _row("Peak Knee Valgus",
             _bilateral(valgus, lambda v: _fmt_deg(v))) +
        _row("Bilateral Asymmetry",
             f"{asym_pct:.1f}%  {'⚠ above threshold' if asym_pct > 15 else '✓ within range'}") +
        (_row("Trunk Lean", _fmt_deg(trunk)) if trunk is not None else "")
    )

    # Provenance row
    prov_note = f"Multi-view 3D ({n_views} cameras)" if product == "studio" else "2D two-view"
    if recon_conf is not None:
        prov_note += f" · reconstruction confidence {recon_conf*100:.0f}%"

    # Recommendations
    rec_items = "".join(f"<li>{r}</li>" for r in _recommendations(result))

    # Assessor / notes section (optional)
    assessor_block = ""
    if assessor or notes:
        assessor_block = f"""
      <div class="sig-block">
        {"<div class='sig-line'>Assessor: " + assessor + "</div>" if assessor else ""}
        {"<div class='sig-note'>" + notes + "</div>" if notes else ""}
      </div>"""

    html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>LANDR Studio Report — {athlete_name}</title>
<style>
  /* ── Screen defaults ── */
  :root {{
    --bg:#f9fafb; --panel:#ffffff; --line:#e5e7eb; --text:#111827;
    --muted:#6b7280; --faint:#9ca3af; --accent:#0284c7;
    --good:#16a34a; --warn:#d97706; --bad:#dc2626;
    --mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  }}
  * {{ box-sizing:border-box; margin:0; padding:0; }}
  body {{
    background:var(--bg); color:var(--text); font-family:var(--sans);
    font-size:14px; line-height:1.55; -webkit-font-smoothing:antialiased;
  }}
  .page {{ max-width:820px; margin:0 auto; padding:40px 48px 60px; }}

  /* ── Header ── */
  .report-header {{
    display:flex; justify-content:space-between; align-items:flex-start;
    padding-bottom:20px; border-bottom:2px solid var(--text); margin-bottom:24px;
  }}
  .report-header .brand {{ font-size:22px; font-weight:800; letter-spacing:-.02em; }}
  .report-header .brand span {{ color:var(--accent); }}
  .report-header .meta {{ font-size:12px; color:var(--muted); text-align:right; line-height:1.7; }}

  /* ── Section headings ── */
  h2 {{
    font-size:11px; font-weight:700; letter-spacing:.12em; text-transform:uppercase;
    color:var(--muted); margin:28px 0 10px; border-bottom:1px solid var(--line);
    padding-bottom:6px;
  }}

  /* ── Risk block ── */
  .risk-block {{
    background:{risk_bg}; border:1px solid {risk_col}40;
    border-left:4px solid {risk_col};
    border-radius:8px; padding:20px 22px;
    display:flex; align-items:center; gap:24px;
  }}
  .risk-score {{ text-align:center; }}
  .risk-score .num {{
    font-size:52px; font-family:var(--mono); font-weight:800;
    line-height:1; color:{risk_col};
  }}
  .risk-score .denom {{ font-size:13px; color:var(--muted); }}
  .risk-detail {{ flex:1; }}
  .risk-detail .cat {{
    font-size:22px; font-weight:800; letter-spacing:-.01em; color:{risk_col};
    text-transform:uppercase;
  }}
  .risk-detail .rat {{ font-size:13px; color:var(--muted); margin-top:4px; max-width:440px; }}
  .less-badge {{
    text-align:center; min-width:64px; padding:12px 16px;
    background:white; border-radius:8px; border:1px solid {risk_col}30;
  }}
  .less-badge .n {{ font-size:32px; font-family:var(--mono); font-weight:700; color:{risk_col}; }}
  .less-badge .lbl {{ font-size:11px; color:var(--muted); margin-top:2px; }}

  /* ── LESS table ── */
  table.less {{ width:100%; border-collapse:collapse; }}
  table.less tr.err {{ background:#fef9f9; }}
  table.less tr.ok  {{ background:transparent; }}
  table.less td {{ padding:8px 10px; border-bottom:1px solid var(--line); font-size:13px; }}
  table.less td.chk {{ width:28px; font-weight:800; font-size:15px; text-align:center; }}
  table.less td.desc {{ }}
  table.less .detail {{ display:block; font-size:11px; color:var(--muted); margin-top:2px; }}

  /* ── Metrics table ── */
  table.metrics {{ width:100%; border-collapse:collapse; }}
  table.metrics td {{ padding:9px 10px; border-bottom:1px solid var(--line); font-size:13px; }}
  table.metrics td.ml {{ color:var(--muted); width:52%; }}
  table.metrics td.mv {{ font-family:var(--mono); font-weight:600; }}

  /* ── Recommendations ── */
  .recs ol {{ padding-left:18px; }}
  .recs li {{ margin-bottom:10px; font-size:13px; line-height:1.6; }}

  /* ── Provenance ── */
  .prov {{ font-size:11.5px; color:var(--muted); line-height:1.7; }}

  /* ── Signature block ── */
  .sig-block {{ margin-top:24px; padding-top:20px; border-top:1px solid var(--line); }}
  .sig-line {{ font-size:13px; margin-bottom:6px; }}
  .sig-note {{ font-size:12px; color:var(--muted); }}

  /* ── Print button (screen only) ── */
  .print-bar {{
    display:flex; justify-content:flex-end; gap:10px; margin-bottom:28px;
  }}
  .print-btn {{
    font:inherit; font-size:13px; font-weight:600; cursor:pointer;
    padding:9px 20px; border-radius:7px; border:1px solid var(--line);
    background:var(--panel); color:var(--text);
  }}
  .print-btn.primary {{
    background:var(--accent); color:#fff; border-color:var(--accent);
  }}

  /* ── Print overrides ── */
  @media print {{
    body {{ background:white; font-size:12px; }}
    .page {{ max-width:100%; padding:0; }}
    .print-bar {{ display:none; }}
    h2 {{ page-break-after:avoid; }}
    .risk-block {{ page-break-inside:avoid; }}
    table.less tr {{ page-break-inside:avoid; }}
    a {{ color:inherit; text-decoration:none; }}
  }}
</style>
</head>
<body>
<div class="page">

  <div class="print-bar">
    <button class="print-btn" onclick="window.close()">Close</button>
    <button class="print-btn primary" onclick="window.print()">Print / Save PDF</button>
  </div>

  <div class="report-header">
    <div>
      <div class="brand">LANDR <span>Studio</span></div>
      <div style="font-size:13px;color:var(--muted);margin-top:4px;">
        ACL-Risk Landing Analysis
      </div>
    </div>
    <div class="meta">
      <strong>{athlete_name}</strong><br/>
      {session_label}<br/>
      {today}
    </div>
  </div>

  <!-- ── Risk summary ── -->
  <h2>Overall Risk</h2>
  <div class="risk-block">
    <div class="risk-score">
      <div class="num">{risk.score_0_100:.0f}</div>
      <div class="denom">/ 100</div>
    </div>
    <div class="risk-detail">
      <div class="cat">{risk.category} risk</div>
      <div class="rat">{risk.rationale}</div>
    </div>
    <div class="less-badge">
      <div class="n">{less.total}</div>
      <div class="lbl">LESS<br/>errors</div>
    </div>
  </div>

  <!-- ── LESS checklist ── -->
  <h2>Landing Error Scoring System (LESS)</h2>
  <table class="less">
    <tbody>
      {less_rows}
    </tbody>
  </table>

  <!-- ── Key metrics ── -->
  <h2>Key Biomechanical Metrics</h2>
  <table class="metrics">
    <tbody>
      {metric_rows}
    </tbody>
  </table>

  <!-- ── Recommendations ── -->
  <h2>Clinical Recommendations</h2>
  <div class="recs">
    <ol>{rec_items}</ol>
  </div>

  <!-- ── Provenance ── -->
  <h2>Analysis Provenance</h2>
  <div class="prov">
    Method: {prov_note}<br/>
    Landing events: initial contact frame {events.initial_contact},
    lowest point frame {events.lowest_point},
    stabilised frame {events.stabilized}<br/>
    LANDR Studio · Generated {today}
  </div>

  {assessor_block}

</div>
</body>
</html>"""

    return html
