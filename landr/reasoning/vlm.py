"""Pluggable report generator.

Providers
---------
* ``mock``   : deterministic, offline, templated report. No network, no keys.
* ``openai`` : GPT-4o family via the official ``openai`` SDK (needs OPENAI_API_KEY).
* ``gemini`` : Gemini family via ``google-generativeai`` (needs GOOGLE_API_KEY).

All providers share the same prompt. Any provider failure degrades to the mock.
"""

from __future__ import annotations

import os
from typing import Any

from ..types import AnalysisResult, LessResult, RiskResult
from . import prompts
from .drills import drills_for


def _mock_report(metrics, less, risk, drills, athlete) -> str:
    ic = metrics["at_initial_contact"]
    low = metrics["at_lowest_point"]
    errors = less.errors()
    who = (athlete or {}).get("name", "This athlete")

    risk_phrase = {"low": "low-risk", "moderate": "moderately elevated-risk",
                   "high": "elevated-risk"}.get(risk.category, risk.category)

    lines: list[str] = []
    lines.append("# LANDR Landing Screening Report\n")
    lines.append(
        f"**Summary.** {who} shows a **{risk_phrase}** landing pattern "
        f"(risk score {risk.score_0_100}/100; automated LESS {less.total}). "
        f"This is a screening aid, not a diagnosis.\n"
    )
    lines.append("**What we saw.**")
    lines.append(
        f"- At initial contact: knee flexion {ic['knee_flexion_deg']}°, "
        f"knee valgus {ic['knee_valgus_deg']}°, trunk flexion {ic['trunk_flexion_deg']}°."
    )
    lines.append(
        f"- At the deepest point: knee flexion {low['knee_flexion_deg']}°, "
        f"knee valgus {low['knee_valgus_deg']}°."
    )
    lines.append(
        f"- Knee-flexion range used to absorb the landing: "
        f"{metrics['knee_flexion_displacement_deg']}°."
    )
    lines.append(
        f"- Peak knee valgus: left {metrics['peak_valgus_deg']['left']}°, "
        f"right {metrics['peak_valgus_deg']['right']}°; "
        f"asymmetry index {metrics['asymmetry_index']}."
    )
    if errors:
        lines.append("\n**Flagged movement patterns:**")
        for e in errors:
            lines.append(f"- {e.description} ({e.detail}).")
    else:
        lines.append("\nNo individual high-risk patterns were flagged. Nice work.")

    lines.append("\n**What to work on.**")
    for d in drills:
        lines.append(f"- {d}")

    lines.append("\n**Next steps.**")
    if risk.category == "high":
        lines.append("- Consider a movement assessment with a physical therapist or athletic trainer.")
    lines.append("- Re-screen in 6-8 weeks to track progress.")
    lines.append(
        "\n_LANDR is decision-support for screening only and does not diagnose "
        "injury. Always keep a qualified clinician in the loop._"
    )
    return "\n".join(lines)


class ReportGenerator:
    """Builds a plain-language report from an analysis, via a chosen provider."""

    def __init__(self, provider: str = "mock", model: str | None = None) -> None:
        self.provider = provider
        self.model = model

    def generate(self, metrics, less: LessResult, risk: RiskResult, athlete=None):
        """Return ``(report_text, provider_used)``; falls back to mock on error."""
        drills = drills_for([e.key for e in less.errors()])

        if self.provider == "mock":
            return _mock_report(metrics, less, risk, drills, athlete), "mock"

        try:
            if self.provider == "openai":
                return self._openai(metrics, less, risk, drills, athlete), "openai"
            if self.provider == "gemini":
                return self._gemini(metrics, less, risk, drills, athlete), "gemini"
            raise ValueError(f"Unknown provider: {self.provider}")
        except Exception as exc:
            fallback = _mock_report(metrics, less, risk, drills, athlete)
            note = (
                f"\n\n> ⚠️ VLM provider '{self.provider}' unavailable "
                f"({type(exc).__name__}: {exc}); showing the offline report instead."
            )
            return fallback + note, "mock(fallback)"

    def _openai(self, metrics, less, risk, drills, athlete) -> str:
        from openai import OpenAI
        if not os.environ.get("OPENAI_API_KEY"):
            raise RuntimeError("OPENAI_API_KEY not set")
        client = OpenAI()
        model = self.model or "gpt-4o"
        user = prompts.build_user_prompt(metrics, less.as_dict(), risk.as_dict(), drills, athlete)
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": prompts.SYSTEM_PROMPT},
                {"role": "user", "content": user},
            ],
            temperature=0.4,
        )
        return resp.choices[0].message.content or ""

    def _gemini(self, metrics, less, risk, drills, athlete) -> str:
        import google.generativeai as genai
        key = os.environ.get("GOOGLE_API_KEY")
        if not key:
            raise RuntimeError("GOOGLE_API_KEY not set")
        genai.configure(api_key=key)
        model_name = self.model or "gemini-1.5-pro"
        model = genai.GenerativeModel(model_name, system_instruction=prompts.SYSTEM_PROMPT)
        user = prompts.build_user_prompt(metrics, less.as_dict(), risk.as_dict(), drills, athlete)
        resp = model.generate_content(user)
        return resp.text or ""


def generate_report(result: AnalysisResult, provider="mock", model=None, athlete=None):
    """Convenience wrapper used by the pipeline."""
    return ReportGenerator(provider=provider, model=model).generate(
        result.metrics, result.less, result.risk, athlete
    )
