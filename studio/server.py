"""LANDR Studio backend + dashboard server (separate product from the mobile API).

Endpoints:
    GET  /                         -> the Studio clinician dashboard (web/index.html)
    GET  /api/demo?profile=...     -> run the real pipeline on a synthetic capture
    GET  /api/selftest             -> the geometry validation numbers (proven, live)
    POST /api/analyze              -> analyse a real multi-view capture (rig + keypoints)
    GET  /report?profile=...       -> printable HTML clinical report for a demo profile
    WS   /ws/live                  -> live multi-camera streaming + real-time rep results

Run:  python -m studio.server        (serves http://localhost:8010)
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

from .calibration import CameraRig
from .demo import make_demo_result
from .live import LiveBridge
from .pipeline import CaptureView, analyze_capture

app = FastAPI(title="LANDR Studio — Multi-Camera Biomechanics")

# One bridge instance — supports one live session at a time.
_bridge = LiveBridge()

_WEB = Path(__file__).parent / "web"


@app.get("/")
def dashboard() -> FileResponse:
    return FileResponse(_WEB / "index.html")


_DEMO_CACHE: dict[str, dict[str, Any]] = {}


@app.get("/api/demo")
def demo(profile: str = "good") -> JSONResponse:
    """Analyse a ready-made synthetic capture through the full 3D pipeline.

    Results are cached per profile: the pipeline is deterministic, so a capture only
    needs analysing once (the first call runs the real triangulation, ~1.5 s).
    """
    try:
        if profile not in _DEMO_CACHE:
            _DEMO_CACHE[profile] = make_demo_result(profile).as_dict()
        return JSONResponse(_DEMO_CACHE[profile])
    except Exception as exc:  # pragma: no cover
        return JSONResponse(status_code=400, content={"error": str(exc)})


@app.get("/api/selftest")
def selftest() -> JSONResponse:
    """Return the live geometry-validation numbers (see studio.selftest)."""
    from .selftest import run

    return JSONResponse(run())


@app.post("/api/analyze")
def analyze(payload: dict[str, Any]) -> JSONResponse:
    """Analyse a real capture.

    Body: {"rig": <CameraRig.to_dict()>,
           "views": [{"keypoints": (T,J,2), "confidences": (T,J)}, ...],
           "athlete": {...}}
    Views are bound to rig cameras by order.
    """
    try:
        rig = CameraRig.from_dict(payload["rig"])
        views = []
        for cam, v in zip(rig.cameras, payload["views"]):
            views.append(
                CaptureView(
                    camera=cam,
                    keypoints=np.array(v["keypoints"], float),
                    confidences=(
                        np.array(v["confidences"], float) if v.get("confidences") else None
                    ),
                )
            )
        result = analyze_capture(views, rig, athlete=payload.get("athlete"))
        return JSONResponse(result.as_dict())
    except Exception as exc:  # pragma: no cover
        return JSONResponse(status_code=400, content={"error": str(exc)})


@app.get("/report")
def report(profile: str = "good", athlete: str = "", session: str = "") -> HTMLResponse:
    """Return a print-optimized HTML clinical report for a demo profile.

    Open in a browser tab and use File > Print (or Ctrl-P) to save as PDF.
    """
    from .report import render_report

    try:
        if profile not in _DEMO_CACHE:
            _DEMO_CACHE[profile] = make_demo_result(profile).as_dict()
        result = make_demo_result(profile)
        athlete_name = athlete or result.meta.get("athlete", {}).get("name", "Athlete")
        html = render_report(result, athlete_name=athlete_name, session_id=session)
        return HTMLResponse(html)
    except Exception as exc:  # pragma: no cover
        return HTMLResponse(f"<pre>Error: {exc}</pre>", status_code=400)


@app.websocket("/ws/live")
async def live_ws(ws: WebSocket) -> None:
    """Live session WebSocket.

    Client → server messages (JSON):
      {"action":"start","sources":[0,1,2,3],"rig":{...},"athlete":{},"device":"cpu"}
      {"action":"stop"}

    Server → client messages (JSON):
      {"type":"frame","frame":N,"state":"IDLE|FALLING|RECOVERING","hip_y":1.02,"cameras_ok":[true,...]}
      {"type":"rep","result":{...}}   — full AnalysisResult.as_dict() after each rep
      {"type":"status","running":bool}
      {"type":"error","message":"..."}
    """
    await ws.accept()
    try:
        while True:
            # Handle incoming commands (non-blocking; fall through if no message).
            try:
                raw = await ws.receive_text()
                msg = json.loads(raw)
                action = msg.get("action")

                if action == "start":
                    if _bridge.running:
                        _bridge.stop()
                    sources = msg.get("sources", [0])
                    rig_dict = msg.get("rig")
                    if rig_dict is None:
                        await ws.send_text(json.dumps({"type": "error",
                            "message": "rig is required to start a live session"}))
                        continue
                    try:
                        rig = CameraRig.from_dict(rig_dict)
                        _bridge.start(
                            sources=sources,
                            rig=rig,
                            athlete=msg.get("athlete"),
                            device=msg.get("device", "cpu"),
                        )
                        await ws.send_text(json.dumps({"type": "status", "running": True}))
                    except Exception as exc:
                        await ws.send_text(json.dumps({"type": "error", "message": str(exc)}))

                elif action == "stop":
                    _bridge.stop()
                    await ws.send_text(json.dumps({"type": "status", "running": False}))

            except Exception:
                pass  # no message or parse error — drain the queue instead

            # Drain and forward any pending messages from the live session.
            import asyncio
            import queue as _q
            sent = 0
            while sent < 20:  # max 20 messages per WS tick to stay responsive
                try:
                    item = _bridge._q.get_nowait()
                    await ws.send_text(json.dumps(item))
                    sent += 1
                except _q.Empty:
                    break

            await asyncio.sleep(0.033)  # ~30 fps WS tick

    except WebSocketDisconnect:
        _bridge.stop()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8010)
