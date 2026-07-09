"""Print the real OpenCap folder layout so adapter.py can be finalised.

Usage (after unzipping the download):
    python -m validation.discover_cli "C:/Users/sagar/opencap_data/LabValidation_withVideos"
"""

from __future__ import annotations

import sys

from .adapter import discover


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    print(discover(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
