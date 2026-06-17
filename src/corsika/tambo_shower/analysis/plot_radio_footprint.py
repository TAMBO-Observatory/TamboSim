#!/usr/bin/env python3
"""Compute per-antenna radio energy fluence and render a shower-plane footprint.

Given a ``--radio`` run directory produced by the ``tambo_shower`` CORSIKA 8
application, this script:

  1. loads the per-observer CoREAS waveforms, antenna positions and shower
     geometry (:func:`load_run`),
  2. computes the energy fluence for each antenna (:func:`energy_fluence`),
  3. projects the antenna positions into the shower plane spanned by the
     ``v x B`` and ``v x (v x B)`` axes (:func:`project_to_shower_plane`),
  4. renders a log-color-scale PNG footprint (:func:`plot_footprint`).

The three "math" functions are deliberately independent of any CORSIKA file
IO so they can be unit-tested with synthetic numpy data.

On-disk format (see ``src/.../src/RADIO_NOTES.md`` section 9 and the writer
source ``corsika/detail/modules/radio/RadioProcess.inl``):

  ``<run_dir>/radio/`` contains
    * ``antennas.csv``         -- header ``id,vertex_index,x,y,z`` (ECEF metres),
                                  one row per observer, ``id`` 0-based.
    * ``shower_geometry.csv``  -- one data row with core/dir/B.
    * ``observers.parquet``    -- columns ``shower, Time, Ex, Ey, Ez``.

  The parquet has NO per-observer id column. The ``ParquetStreamer`` prepends a
  ``shower`` (uint32 event id) column, then the RadioProcess writer streams
  ``Time, Ex, Ey, Ez`` per time sample. ``endOfShower`` loops over observers in
  collection-insertion order and writes ``axis.size()-1`` contiguous rows for
  each. Since every observer shares the same ``duration``/``sampleRate``, all
  observers produce the same number of samples, so rows are split into N_obs
  equal contiguous chunks (per shower id) ordered to match ``antennas.csv``'s
  ``id`` order (the C++ side adds observers in id order, naming each
  ``std::to_string(id)``).
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import numpy as np

# Physical constants (SI) plus the eV conversion.
EPS0 = 8.8541878128e-12  # vacuum permittivity [F/m]
C = 2.99792458e8         # speed of light [m/s]
EV = 1.602176634e-19     # 1 eV in joules [J/eV]

# Times in the parquet/observer waveforms are stored in nanoseconds.
NS_TO_S = 1e-9


# --------------------------------------------------------------------------- #
# Pure math (no CORSIKA IO) -- unit tested directly.
# --------------------------------------------------------------------------- #
def energy_fluence(times, ex, ey, ez):
    """Energy fluence of a single antenna waveform, in eV/m^2.

    Computes ``eps0 * c * sum(|E|^2) * dt`` (the time-integrated Poynting
    flux for a plane wave in vacuum) in J/m^2, then converts to eV/m^2.

    Parameters
    ----------
    times : array_like
        Sample times in NANOSECONDS.
    ex, ey, ez : array_like
        Electric-field components in V/m, aligned with ``times``.

    Returns
    -------
    float
        Energy fluence in eV/m^2.
    """
    times = np.asarray(times, dtype=float)
    ex = np.asarray(ex, dtype=float)
    ey = np.asarray(ey, dtype=float)
    ez = np.asarray(ez, dtype=float)

    times_s = times * NS_TO_S
    dt = float(np.median(np.diff(times_s)))

    e2 = ex * ex + ey * ey + ez * ez
    fluence_j_m2 = EPS0 * C * float(np.sum(e2)) * dt
    return fluence_j_m2 / EV


def project_to_shower_plane(positions, core, v, B):
    """Project antenna positions into the (v x B, v x (v x B)) shower plane.

    Parameters
    ----------
    positions : array_like, shape (N, 3)
        Antenna positions (ECEF metres).
    core : array_like, shape (3,)
        Shower core position (ECEF metres).
    v : array_like, shape (3,)
        Shower propagation direction.
    B : array_like, shape (3,)
        Magnetic field vector (only its direction matters).

    Returns
    -------
    (a, b) : tuple of ndarray, shape (N,)
        ``a = (r - core) . e1`` with ``e1 = (v x B) / |v x B|`` and
        ``b = (r - core) . e2`` with ``e2 = (v x (v x B)) / |v x (v x B)|``.
    """
    positions = np.asarray(positions, dtype=float).reshape(-1, 3)
    core = np.asarray(core, dtype=float).reshape(3)
    v = np.asarray(v, dtype=float).reshape(3)
    B = np.asarray(B, dtype=float).reshape(3)

    vxB = np.cross(v, B)
    e1 = vxB / np.linalg.norm(vxB)

    vxvxB = np.cross(v, vxB)
    e2 = vxvxB / np.linalg.norm(vxvxB)

    rel = positions - core
    a = rel @ e1
    b = rel @ e2
    return a, b


def plot_footprint(a, b, fluence_eV_m2, out_png, title=None):
    """Render a log-color-scale shower-plane footprint to ``out_png``.

    Parameters
    ----------
    a, b : array_like, shape (N,)
        Shower-plane coordinates along v x B and v x (v x B) [m].
    fluence_eV_m2 : array_like, shape (N,)
        Per-antenna energy fluence [eV/m^2] used for color.
    out_png : str or Path
        Output PNG path. Parent directories are created.
    title : str, optional
        Plot title.

    Returns
    -------
    Path
        The path that was written.
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LogNorm

    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    fluence = np.asarray(fluence_eV_m2, dtype=float)

    # LogNorm cannot handle zero/negative values: clip them to the smallest
    # positive fluence (or 1 if none are positive).
    positive = fluence[fluence > 0]
    floor = float(positive.min()) if positive.size else 1.0
    fluence_clipped = np.where(fluence > 0, fluence, floor)
    vmax = float(fluence_clipped.max())

    out_png = Path(out_png)
    out_png.parent.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(7, 6))
    sc = ax.scatter(
        a, b, c=fluence_clipped,
        norm=LogNorm(vmin=floor, vmax=vmax),
        cmap="viridis", s=40, edgecolors="none",
    )
    ax.set_xlabel("v×B [m]")
    ax.set_ylabel("v×(v×B) [m]")
    ax.set_aspect("equal")
    if title:
        ax.set_title(title)
    cbar = fig.colorbar(sc, ax=ax)
    cbar.set_label("energy fluence [eV/m²]")

    fig.tight_layout()
    fig.savefig(out_png, dpi=150)
    plt.close(fig)
    return out_png


# --------------------------------------------------------------------------- #
# CORSIKA IO -- not locally testable without real output.
# --------------------------------------------------------------------------- #
def _read_antennas_csv(path):
    """Read antennas.csv -> (ids sorted, positions Nx3) ordered by id."""
    rows = []
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            rows.append(
                (int(row["id"]), float(row["x"]), float(row["y"]), float(row["z"]))
            )
    rows.sort(key=lambda r: r[0])
    ids = np.array([r[0] for r in rows], dtype=int)
    positions = np.array([[r[1], r[2], r[3]] for r in rows], dtype=float)
    return ids, positions


def _read_shower_geometry_csv(path):
    """Read shower_geometry.csv -> (core 3, v 3, B 3)."""
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        row = next(reader)
    core = np.array(
        [float(row["core_x"]), float(row["core_y"]), float(row["core_z"])],
        dtype=float,
    )
    v = np.array(
        [float(row["dir_x"]), float(row["dir_y"]), float(row["dir_z"])],
        dtype=float,
    )
    B = np.array(
        [float(row["bx_nT"]), float(row["by_nT"]), float(row["bz_nT"])],
        dtype=float,
    )
    return core, v, B


def _find_parquet(radio_dir):
    """Locate observers.parquet under the radio output dir."""
    direct = radio_dir / "observers.parquet"
    if direct.is_file():
        return direct
    # OutputManager places it in a per-process subdir; search recursively.
    matches = sorted(radio_dir.rglob("observers.parquet"))
    if not matches:
        raise FileNotFoundError(f"observers.parquet not found under {radio_dir}")
    return matches[0]


def load_run(run_dir):
    """Load a ``--radio`` run directory.

    Parameters
    ----------
    run_dir : str or Path
        The run directory (its ``radio/`` subdir holds the radio output).

    Returns
    -------
    (positions, core, v, B, traces)
        ``positions`` : ndarray (N, 3) antenna ECEF positions ordered by id.
        ``core, v, B`` : ndarray (3,).
        ``traces`` : list of length N, aligned with ``positions``; each element
        is ``(times, ex, ey, ez)`` arrays for that antenna (times in ns).
    """
    import pyarrow.parquet as pq

    run_dir = Path(run_dir)
    radio_dir = run_dir / "radio"
    if not radio_dir.is_dir():
        # Allow passing the radio dir itself.
        radio_dir = run_dir

    ids, positions = _read_antennas_csv(radio_dir / "antennas.csv")
    core, v, B = _read_shower_geometry_csv(radio_dir / "shower_geometry.csv")

    n_obs = len(ids)

    table = pq.read_table(_find_parquet(radio_dir))
    cols = {name.lower(): name for name in table.column_names}

    def col(name):
        return np.asarray(table.column(cols[name]).to_numpy(), dtype=float)

    time = col("time")
    ex = col("ex")
    ey = col("ey")
    ez = col("ez")

    # If multiple showers are present, keep only the first event so the row
    # layout (N_obs equal contiguous chunks) is well defined.
    if "shower" in cols:
        shower = np.asarray(table.column(cols["shower"]).to_numpy())
        first = shower[0]
        n_showers = np.unique(shower).size
        if n_showers > 1:
            print(
                f"[plot_radio_footprint] note: {n_showers} showers in the parquet; "
                f"plotting only the first (shower id {first}).",
                file=sys.stderr,
            )
        mask = shower == first
        time, ex, ey, ez = time[mask], ex[mask], ey[mask], ez[mask]

    total = time.shape[0]
    traces = []
    if n_obs > 0 and total > 0:
        if total % n_obs != 0:
            raise ValueError(
                f"parquet has {total} rows, not divisible by {n_obs} antennas; "
                "cannot split into per-observer contiguous chunks."
            )
        per = total // n_obs
        for i in range(n_obs):
            sl = slice(i * per, (i + 1) * per)
            traces.append((time[sl], ex[sl], ey[sl], ez[sl]))
    else:
        traces = [
            (np.empty(0), np.empty(0), np.empty(0), np.empty(0))
            for _ in range(n_obs)
        ]

    return positions, core, v, B, traces


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Render a radio energy-fluence footprint from a "
        "tambo_shower --radio run."
    )
    parser.add_argument("run_dir", help="run directory (contains radio/)")
    parser.add_argument("-o", "--output", required=True, help="output PNG path")
    parser.add_argument("--title", default=None, help="plot title")
    args = parser.parse_args(argv)

    positions, core, v, B, traces = load_run(args.run_dir)
    fluence = np.array(
        [energy_fluence(t, ex, ey, ez) for (t, ex, ey, ez) in traces],
        dtype=float,
    )
    a, b = project_to_shower_plane(positions, core, v, B)
    out = plot_footprint(a, b, fluence, args.output, title=args.title)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
