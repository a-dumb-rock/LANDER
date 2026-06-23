"""Optional plotting (matplotlib imported lazily)."""

from __future__ import annotations

from typing import Any

from .types import AnalysisResult


def plot_analysis(result: AnalysisResult, out_path: str) -> str:
    """Save a multi-panel plot of the key angle time-series to ``out_path``."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    s: dict[str, Any] = result.metrics["series"]
    t = s["time_s"]
    ev = result.events

    def vlines(ax):
        for frame, label, color in [
            (ev.initial_contact, "contact", "tab:green"),
            (ev.lowest_point, "lowest", "tab:red"),
            (ev.stabilized, "stable", "tab:gray"),
        ]:
            if 0 <= frame < len(t):
                ax.axvline(t[frame], ls="--", lw=1, color=color, alpha=0.7, label=label)

    fig, axes = plt.subplots(3, 1, figsize=(9, 9), sharex=True)
    axes[0].plot(t, s["knee_flexion_left"], label="left")
    axes[0].plot(t, s["knee_flexion_right"], label="right")
    axes[0].set_ylabel("Knee flexion (deg)")
    axes[0].set_title(
        f"LANDR — risk {result.risk.category.upper()} "
        f"(score {result.risk.score_0_100}/100, LESS {result.less.total})"
    )
    axes[1].plot(t, s["knee_valgus_left"], label="left")
    axes[1].plot(t, s["knee_valgus_right"], label="right")
    axes[1].axhline(0, color="k", lw=0.6)
    axes[1].set_ylabel("Knee valgus (deg)\n(+ = medial collapse)")
    axes[2].plot(t, s["trunk_flexion"], color="tab:purple", label="trunk")
    axes[2].set_ylabel("Trunk flexion (deg)")
    axes[2].set_xlabel("Time (s)")

    for ax in axes:
        vlines(ax)
        handles, labels = ax.get_legend_handles_labels()
        seen: dict[str, Any] = {}
        for h, l in zip(handles, labels):
            seen.setdefault(l, h)
        ax.legend(seen.values(), seen.keys(), fontsize=8, loc="best")
        ax.grid(alpha=0.2)

    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    return out_path


def plot_fatigue(fresh: AnalysisResult, fatigued: AnalysisResult, out_path: str) -> str:
    """Overlay fresh vs fatigued knee-valgus curves to visualize degradation."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sf, sg = fresh.metrics["series"], fatigued.metrics["series"]
    fig, ax = plt.subplots(figsize=(9, 5))
    for series, lbl, style in ((sf, "fresh", "-"), (sg, "fatigued", "--")):
        ax.plot(series["time_s"], series["knee_valgus_left"], style,
                label=f"{lbl} (left)")
        ax.plot(series["time_s"], series["knee_valgus_right"], style,
                label=f"{lbl} (right)", alpha=0.7)
    ax.axhline(0, color="k", lw=0.6)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Knee valgus (deg)  (+ = medial collapse)")
    ax.set_title("Fatigue degrades landing mechanics (fresh vs fatigued)")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.2)
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    return out_path
