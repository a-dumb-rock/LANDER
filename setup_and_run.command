#!/bin/bash
# LANDR — one-click setup & demo (macOS / Linux)
# Double-click this file in Finder, OR run it from a terminal:  bash setup_and_run.command

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

echo "========================================================"
echo "  LANDR v2 setup & demo  (accuracy + fatigue)"
echo "  Folder: $DIR"
echo "========================================================"
echo

pause_exit () { echo; read -n 1 -s -r -p "Press any key to close..."; echo; exit "${1:-0}"; }

if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo "❌ Python 3 is not installed."
  echo "   Install it from https://www.python.org/downloads/ and run this again."
  pause_exit 1
fi
echo "✅ Using $($PY --version)"
echo

PYBIN="$PY"; PIPFLAGS=""
if [ -f ".venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate && PYBIN="python"
else
  echo "📦 Creating virtual environment (.venv)..."
  if $PY -m venv .venv 2>/dev/null && [ -f ".venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate && PYBIN="python"
  else
    echo "⚠️  Couldn't create a virtual environment; using your system Python."
    PIPFLAGS="--user"
  fi
fi

echo "📥 Installing dependencies (numpy, scipy, matplotlib)..."
install_pkgs () {
  $PYBIN -m pip install --quiet $PIPFLAGS "$@" 2>/dev/null \
    || $PYBIN -m pip install --quiet $PIPFLAGS --break-system-packages "$@" 2>/dev/null \
    || $PYBIN -m pip install $PIPFLAGS "$@"
}
install_pkgs --upgrade pip >/dev/null 2>&1
install_pkgs numpy scipy matplotlib

if ! $PYBIN -c "import numpy, scipy" 2>/dev/null; then
  echo "❌ Could not install numpy/scipy automatically."
  echo "   Try manually:  $PYBIN -m pip install numpy scipy matplotlib"
  pause_exit 1
fi

echo
echo "========================================================"
echo "  1) Basic screen (high-risk synthetic landing)"
echo "========================================================"
$PYBIN -m landr.cli demo --quality poor --plot landr_poor.png

echo
echo "========================================================"
echo "  2) Fatigue-vulnerability (Pillar 2: fresh vs fatigued)"
echo "========================================================"
$PYBIN -m landr.cli fatigue --plot landr_fatigue.png

echo
echo "========================================================"
echo "  3) Accuracy benchmark (Pillar 1: error reduction)"
echo "========================================================"
$PYBIN -m landr.cli benchmark

echo
echo "✅ Done. Plots saved in this folder:"
echo "   landr_poor.png        (angle curves)"
echo "   landr_fatigue.png     (fresh vs fatigued)"
if command -v open >/dev/null 2>&1; then
  open landr_fatigue.png >/dev/null 2>&1 || true
fi

echo
echo "Tip: analyze a real video later with:"
echo "   source .venv/bin/activate        # if a .venv was created"
echo "   pip install mediapipe opencv-python"
echo "   python -m landr.cli analyze /path/to/your_jump.mp4 --plot result.png"
pause_exit 0
