"""Tests for LANDR Studio — multi-view 3D reconstruction and analysis.

These assert the *geometry* is correct (triangulation is exact on clean input, the
anatomical frame is orthonormal, DLT recovers a projection, multi-person matching
works) and that the full pipeline runs and serialises. Real-world accuracy is a
separate, data-gated question; see ``studio/README.md``.
"""

import json

import numpy as np
import pytest

from landr import config
from landr.types import AnalysisResult
from studio.anatomical import anatomical_rotation, to_anatomical
from studio.calibration import Camera, CameraRig, calibrate_dlt, make_arc_rig
from studio.demo import make_demo_result
from studio.multiperson import associate_two_views
from studio.pipeline import CaptureView, analyze_capture
from studio.synthetic import make_landing_capture, project_to_views
from studio.triangulation import triangulate_point, triangulate_sequence


def test_camera_project_roundtrip_via_triangulation():
    rig = make_arc_rig(n_cameras=3)
    X = np.array([0.12, -0.05, 1.05])
    obs = np.stack([cam.project(X.reshape(1, 3))[0] for cam in rig.cameras])
    X_hat = triangulate_point(rig.cameras, obs)
    assert np.allclose(X_hat, X, atol=1e-6)


def test_triangulation_sequence_is_exact_on_clean_input():
    rig = make_arc_rig(n_cameras=4)
    world = make_landing_capture(n_frames=12, valgus_gain=3.0, seed=1)
    kp, conf = project_to_views(world, rig, pixel_noise=0.0)
    pts3d, _ = triangulate_sequence(rig.cameras, kp, conf, robust=False)
    used = [config.LEFT_HIP, config.LEFT_KNEE, config.LEFT_ANKLE, config.RIGHT_KNEE]
    err = np.linalg.norm(pts3d[:, used, :] - world.landmarks[:, used, :], axis=-1)
    assert err.max() < 1e-6


def test_triangulation_degrades_gracefully_with_noise():
    rig = make_arc_rig(n_cameras=4)
    world = make_landing_capture(n_frames=20, valgus_gain=3.0, seed=2)
    kp, conf = project_to_views(world, rig, pixel_noise=1.5, seed=3)
    pts3d, _ = triangulate_sequence(rig.cameras, kp, conf, robust=True)
    used = [config.LEFT_KNEE, config.RIGHT_KNEE, config.LEFT_ANKLE]
    err_mm = np.linalg.norm(pts3d[:, used, :] - world.landmarks[:, used, :], axis=-1) * 1000
    assert err_mm.mean() < 15.0  # a few mm with 1.5 px detector noise


def test_anatomical_frame_is_orthonormal():
    rig = make_arc_rig(n_cameras=4)
    world = make_landing_capture(n_frames=10, valgus_gain=3.0, facing_deg=30.0, seed=4)
    R = anatomical_rotation(world, rig.up)
    assert np.allclose(R @ R.T, np.eye(3), atol=1e-9)
    assert np.isclose(np.linalg.det(R), 1.0, atol=1e-9)


def test_anatomical_up_axis_matches_rig_up():
    rig = make_arc_rig(n_cameras=4)
    world = make_landing_capture(n_frames=10, valgus_gain=3.0, seed=5)
    anat = to_anatomical(world, rig.up)
    # In the anatomical frame the shoulders sit above the hips along +y.
    sh_y = anat.landmarks[:, config.LEFT_SHOULDER, 1].mean()
    hip_y = anat.landmarks[:, config.LEFT_HIP, 1].mean()
    assert sh_y > hip_y


def test_dlt_recovers_projection_matrix():
    cam = make_arc_rig(n_cameras=2).cameras[0]
    rng = np.random.default_rng(0)
    X = rng.uniform(-1, 1, size=(30, 3)) + np.array([0, 0, 1.0])
    x = cam.project(X)
    P = calibrate_dlt(X, x)
    # Reproject with the recovered P and compare (P is up to scale).
    Xh = np.hstack([X, np.ones((X.shape[0], 1))])
    proj = (P @ Xh.T).T
    proj = proj[:, :2] / proj[:, 2:3]
    assert np.allclose(proj, x, atol=1e-4)


def test_multiperson_association_matches_correctly():
    rig = make_arc_rig(n_cameras=4)
    p1 = make_landing_capture(n_frames=1, valgus_gain=3.0, seed=6)
    p2 = make_landing_capture(n_frames=1, valgus_gain=9.0, seed=7)
    p2.landmarks[..., 0] += 0.8  # move person 2 sideways in the world
    ca, cb = rig.cameras[0], rig.cameras[3]
    people_a = np.stack([ca.project(p1.landmarks[0]), ca.project(p2.landmarks[0])])
    people_b = np.stack([cb.project(p1.landmarks[0]), cb.project(p2.landmarks[0])])
    conf = np.ones((2, config.NUM_LANDMARKS))
    matches = associate_two_views(ca, cb, people_a, people_b, conf, conf)
    assert sorted(matches) == [(0, 0), (1, 1)]


def test_full_pipeline_runs_and_serialises():
    rig = make_arc_rig(n_cameras=4)
    world = make_landing_capture(n_frames=60, valgus_gain=3.0, seed=8)
    kp, conf = project_to_views(world, rig, pixel_noise=0.5, seed=9)
    views = [
        CaptureView(camera=cam, keypoints=kp[i], confidences=conf[i])
        for i, cam in enumerate(rig.cameras)
    ]
    result = analyze_capture(views, rig, athlete={"name": "Test"})
    assert isinstance(result, AnalysisResult)
    assert result.meta["product"] == "studio"
    assert result.meta["n_views"] == 4
    json.dumps(result.as_dict())  # must be JSON-serialisable


def test_demo_profiles_contrast():
    good = make_demo_result("good")
    at_risk = make_demo_result("at_risk")
    good_peak = max(abs(v) for v in good.metrics["peak_valgus_deg"].values())
    risk_peak = max(abs(v) for v in at_risk.metrics["peak_valgus_deg"].values())
    assert good.risk.category == "low"
    assert at_risk.less.total > good.less.total
    assert risk_peak > good_peak


def test_rig_requires_two_cameras():
    cam = make_arc_rig(n_cameras=2).cameras[0]
    with pytest.raises(ValueError):
        CameraRig(cameras=[cam])
