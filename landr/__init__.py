"""LANDR — Landing Analysis for Non-contact-injury Detection & Risk.

Fatigue-aware ACL injury-risk screening from a single video. See README.md.
"""

__version__ = "0.2.0"

from .pipeline import analyze, analyze_sequence  # noqa: E402,F401
from .multiview import analyze_two_view, analyze_two_view_sequences  # noqa: E402,F401
from .types import AnalysisResult, PoseSequence  # noqa: E402,F401
from .fatigue import compare as compare_fatigue  # noqa: E402,F401
from .accuracy import run_accuracy_benchmark  # noqa: E402,F401

__all__ = [
    "analyze",
    "analyze_sequence",
    "analyze_two_view",
    "analyze_two_view_sequences",
    "AnalysisResult",
    "PoseSequence",
    "compare_fatigue",
    "run_accuracy_benchmark",
    "__version__",
]
