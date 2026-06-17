"""Unit tests for the pure-math functions of plot_radio_footprint.

These tests use synthetic numpy data only -- no CORSIKA output required.
"""

import os

import numpy as np
import pytest

from plot_radio_footprint import (
    C,
    EPS0,
    EV,
    NS_TO_S,
    energy_fluence,
    plot_footprint,
    project_to_shower_plane,
)


def test_energy_fluence_constant_field():
    """Constant unit field over a known grid matches the closed form."""
    # 1 ns spacing, 11 samples (times in ns as in the input file).
    times = np.linspace(0.0, 10.0, 11)
    ex = np.ones_like(times)
    ey = np.ones_like(times)
    ez = np.ones_like(times)

    dt = float(np.median(np.diff(times * NS_TO_S)))
    e2 = ex ** 2 + ey ** 2 + ez ** 2
    expected = EPS0 * C * float(np.sum(e2)) * dt / EV

    got = energy_fluence(times, ex, ey, ez)

    assert got > 0
    assert got == pytest.approx(expected, rel=1e-12)
    # Sanity: dt should be 1 ns = 1e-9 s.
    assert dt == pytest.approx(1e-9, rel=1e-12)


def test_projection_basis():
    """v=(0,0,1), B=(0,1,0) => vxB=+x, vx(vxB)=-y."""
    v = np.array([0.0, 0.0, 1.0])
    B = np.array([0.0, 1.0, 0.0])
    core = np.array([5.0, 7.0, 9.0])

    # A point one metre along +x from the core, plus the core itself.
    positions = np.array(
        [
            core + np.array([1.0, 0.0, 0.0]),  # +x
            core,                              # at core -> origin
            core + np.array([0.0, 1.0, 0.0]),  # +y
        ]
    )

    a, b = project_to_shower_plane(positions, core, v, B)

    # e1 = vxB / |vxB| = (0,1,0)x ... actually v x B = (0,0,1)x(0,1,0) = (-1,0,0)?
    # Compute explicitly: v x B = (vy*Bz - vz*By, vz*Bx - vx*Bz, vx*By - vy*Bx)
    #                          = (0*0 - 1*1, 1*0 - 0*0, 0*1 - 0*0) = (-1, 0, 0)
    # so e1 = (-1,0,0); a point at +x maps to a = -1.
    # v x (v x B) = v x (-1,0,0) = (0*0 - 1*0, 1*(-1) - 0*0, 0*0 - 0*(-1))
    #             = (0, -1, 0); e2 = (0,-1,0).
    # +x point: a = (+x).e1 = -1, b = 0.
    assert a[0] == pytest.approx(-1.0)
    assert b[0] == pytest.approx(0.0)

    # core maps to origin.
    assert a[1] == pytest.approx(0.0)
    assert b[1] == pytest.approx(0.0)

    # +y point: a = 0, b = (+y).e2 = -1.
    assert a[2] == pytest.approx(0.0)
    assert b[2] == pytest.approx(-1.0)


def test_projection_basis_documented_sign():
    """Confirm the documented orientation magnitudes (|a|,|b| == 1)."""
    v = np.array([0.0, 0.0, 1.0])
    B = np.array([0.0, 1.0, 0.0])
    core = np.zeros(3)
    positions = np.array([[1.0, 0.0, 0.0]])
    a, b = project_to_shower_plane(positions, core, v, B)
    assert abs(a[0]) == pytest.approx(1.0)
    assert b[0] == pytest.approx(0.0)


def test_plot_writes_png(tmp_path):
    """Synthetic random data produces a non-empty PNG."""
    rng = np.random.default_rng(42)
    n = 50
    a = rng.uniform(-200, 200, n)
    b = rng.uniform(-200, 200, n)
    fluence = rng.uniform(1e-3, 1e3, n)
    # Include a non-positive value to exercise the LogNorm clipping path.
    fluence[0] = 0.0

    out = tmp_path / "sub" / "footprint.png"
    result = plot_footprint(a, b, fluence, out, title="test footprint")

    assert result == out
    assert out.is_file()
    assert out.stat().st_size > 0


def test_energy_fluence_zero_field():
    """A zero field yields zero fluence."""
    times = np.linspace(0.0, 5.0, 6)
    zeros = np.zeros_like(times)
    assert energy_fluence(times, zeros, zeros, zeros) == pytest.approx(0.0)
