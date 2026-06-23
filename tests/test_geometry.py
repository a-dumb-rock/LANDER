import numpy as np

from landr.biomechanics.geometry import (
    angle_3d,
    flexion_angle,
    frontal_plane_projection_angle,
    signed_knee_valgus,
    trunk_flexion_from_vertical,
)


def test_angle_straight_line_is_180():
    a, b, c = np.array([0, 0, 0.0]), np.array([0, 1, 0.0]), np.array([0, 2, 0.0])
    assert abs(angle_3d(a, b, c) - 180.0) < 1e-6


def test_angle_right_angle():
    a, b, c = np.array([1, 0, 0.0]), np.array([0, 0, 0.0]), np.array([0, 1, 0.0])
    assert abs(angle_3d(a, b, c) - 90.0) < 1e-6


def test_flexion_zero_when_straight():
    a, b, c = np.array([0, 2, 0.0]), np.array([0, 1, 0.0]), np.array([0, 0, 0.0])
    assert flexion_angle(a, b, c) < 1e-6


def test_fppa_nonnegative():
    hip, knee, ankle = np.array([0.0, 1.0, 0.0]), np.array([0.1, 0.5, 0.0]), np.array([0.0, 0.0, 0.0])
    assert frontal_plane_projection_angle(hip, knee, ankle) >= 0


def test_signed_valgus_sign_convention():
    hip, ankle = np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.0, 0.0])
    knee_medial = np.array([0.12, 0.5, 0.0])
    knee_lateral = np.array([-0.12, 0.5, 0.0])
    assert signed_knee_valgus(hip, knee_medial, ankle, "left") > 0
    assert signed_knee_valgus(hip, knee_lateral, ankle, "left") < 0


def test_trunk_flexion_upright_is_zero():
    shoulder, hip = np.array([0.0, 1.5, 0.0]), np.array([0.0, 1.0, 0.0])
    assert trunk_flexion_from_vertical(shoulder, hip) < 1e-6
