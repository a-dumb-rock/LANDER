"""Print a quick summary of synthetic jumps (fresh vs fatigued)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from landr.synthetic import synthetic_jump  # noqa: E402

if __name__ == "__main__":
    for q in ("good", "poor"):
        for fat in (0.0, 0.8):
            seq = synthetic_jump(quality=q, fatigue=fat)
            print(f"{q:>5} fatigue={fat}: {seq.n_frames} frames @ {seq.fps} fps "
                  f"-> {seq.meta['source']}")
