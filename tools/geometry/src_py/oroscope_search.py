"""oroscope_search.py — run an oroscope site search around a point (used by create_geometry.jl --point).

oroscope (https://github.com/mbustama/oroscope) screens a DEM for ground that
can host an observatory, using a JSON configuration of per-experiment criteria. This driver adapts it
to a search *around a point*: the DEM covers the search circle plus the scan's ray range, and an
exclusion zone keeps candidate detector pixels inside the circle (rays still see the terrain around it).

  python oroscope_search.py plan --config CFG --out PLAN.json
      Validates the configuration and writes {"oroscope_version", "walk_km"};
      walk_km is how far the arrival scan traces each ray, so the DEM must reach that far past the circle.

  python oroscope_search.py scan --config CFG --dem DEM.tif --lat LAT --lon LON --radius-km R --outdir DIR
      Runs the search (oroscope's own outputs go to DIR), then writes
        DIR/sites.json         the selected sites (oroscope's records, best first) and the label grid geometry
        DIR/site_labels.bin    int32 label raster (row-major, rows x cols, row 0 = north): pixel value k
                               belongs to sites[k-1]; 0 = no site
"""

import argparse
import json
import math
import os
import sys

R_EARTH_KM = 6371.0


def load_config(path):
    from oroscope import site_searcher as ss
    if not os.path.isfile(path):
        sys.exit(f"oroscope config not found: {path}")
    return ss, ss.load_config(path)


def walk_km(ss, config):
    """How far the arrival scan walks each ray (km), as oroscope resolves it."""
    from oroscope import arrival_scan
    config = {**ss.default_config(), **config}                      # the values the search will use
    max_dist = config["max_dist_km"]
    if config.get("energy_min_pev") and config.get("energy_max_pev"):       # energy range overrides the window
        max_dist = arrival_scan.distance_window_from_energy(config["energy_min_pev"], config["energy_max_pev"])[1] / 1000
    return float(config.get("max_range_km") or max_dist)


def destination(lat, lon, bearing_deg, dist_km):
    """Point `dist_km` from (lat, lon) along `bearing_deg` on a sphere (degrees)."""
    p1, l1, b, d = math.radians(lat), math.radians(lon), math.radians(bearing_deg), dist_km / R_EARTH_KM
    p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b))
    l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1), math.cos(d) - math.sin(p1) * math.sin(p2))
    return math.degrees(p2), math.degrees(l2)


def outside_circle_zone(lat, lon, radius_km, north, south, west, east, n=360):
    """
    oroscope exclusion polygon covering the box [south, north] x [west, east] minus the circle: a
    "keyhole" ring (box, slit in to the circle, circle the other way round, slit back out). oroscope's
    even-odd point-in-polygon test counts the two slit edges twice, so they cancel and only the
    annulus between box and circle is excluded.
    """
    box = [(north, west), (north, east), (south, east), (south, west), (north, west)]
    start = destination(lat, lon, 0.0, radius_km)
    circle = [destination(lat, lon, -360.0 * k / n, radius_km) for k in range(n)] + [start]
    return ("poly", box + circle, "outside the search radius")


def cmd_plan(a):
    import oroscope
    ss, config = load_config(a.config)
    plan = {"oroscope_version": oroscope.__version__, "walk_km": walk_km(ss, config)}
    with open(a.out, "w") as f:
        json.dump(plan, f)


def cmd_scan(a):
    import numpy as np
    import tifffile
    from scipy.ndimage import label
    import oroscope
    ss, config = load_config(a.config)
    os.makedirs(a.outdir, exist_ok=True)

    north, west = ss.read_dem_origin(a.dem)
    cell, rows, cols = ss.read_dem_geometry(a.dem)
    pad = 0.05                                                     # degrees; the box only has to cover the DEM
    zones = list(ss.resolve_rfi_zones(config.get("rfi_zones")) or [])
    zones.append(outside_circle_zone(a.lat, a.lon, a.radius_km, north + pad, north - rows * cell - pad,
                                     west - pad, west + cols * cell + pad))

    overrides = dict(dem_path=os.path.abspath(a.dem), origin_lat=None, origin_lon=None, cell_size_deg=None,
                     rfi_zones=zones, generate_kml=False, resume=False, resume_dir=None,
                     region_name=f"{a.radius_km:g} km around ({a.lat:.5f}, {a.lon:.5f})")
    if config.get("road_map_path"):
        print(f"NOTE: ignoring road_map_path ({config['road_map_path']}): it is aligned to another DEM")
        overrides["road_map_path"] = None
    results = ss.run_from_config(config, run_output_dir=a.outdir, **overrides)

    records = [s for s in results["results"]["sites"] if s.get("selected")]
    unselected = sum(1 for s in results["results"]["sites"] if not s.get("selected"))
    stem = os.path.join(a.outdir, ss.RESULTS_PREFIX + os.path.splitext(os.path.basename(a.dem))[0])
    labels = np.zeros((1, 1), dtype=np.int32); step = cell

    if records and os.path.isfile(stem + ".tif"):
        # The (downsampled) mask of the selected sites; its world file gives oroscope's georeferencing.
        mask = tifffile.imread(stem + ".tif")
        with open(stem + ".tfw") as f:
            tfw = [float(x) for x in f.read().split()]
        step, west, north = tfw[0], tfw[4], tfw[5]
        comp, n = label(mask)                           # oroscope's own labelling (4-connectivity)
        if n != len(records):
            sys.exit(f"oroscope's mask has {n} regions but {len(records)} selected sites; cannot match them")
        # Match components to site records by centroid, computed exactly as oroscope computes it.
        idx = np.arange(1, n + 1)
        from scipy.ndimage import mean as ndi_mean
        rr, cc = np.indices(comp.shape)
        crow = np.atleast_1d(ndi_mean(rr, comp, idx)); ccol = np.atleast_1d(ndi_mean(cc, comp, idx))
        clat = north - crow * step; clon = west + ccol * step
        relabel = np.zeros(n + 1, dtype=np.int32)
        for k, s in enumerate(records, start=1):
            j = int(np.argmin((clat - s["center_lat"]) ** 2 + (clon - s["center_lon"]) ** 2))
            if abs(clat[j] - s["center_lat"]) > step or abs(clon[j] - s["center_lon"]) > step or relabel[j + 1]:
                sys.exit(f"could not match oroscope site {s['site_id']} to a region of its mask")
            relabel[j + 1] = k
        labels = relabel[comp]
    else:
        records = []

    labels.astype("<i4").tofile(os.path.join(a.outdir, "site_labels.bin"))
    out = {"oroscope_version": oroscope.__version__,
           "grid": {"north": north, "west": west, "step_deg": step, "rows": int(labels.shape[0]),
                    "cols": int(labels.shape[1])},
           "sites": records, "n_qualifying_unselected": unselected,
           "total_capacity": results["results"].get("total_capacity"),
           "explanation": results.get("explanation", "")}
    with open(os.path.join(a.outdir, "sites.json"), "w") as f:
        json.dump(out, f, indent=1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    pl = sub.add_parser("plan")
    pl.add_argument("--config", required=True)
    pl.add_argument("--out", required=True)
    sc = sub.add_parser("scan")
    sc.add_argument("--config", required=True)
    sc.add_argument("--dem", required=True)
    sc.add_argument("--lat", type=float, required=True)
    sc.add_argument("--lon", type=float, required=True)
    sc.add_argument("--radius-km", type=float, required=True)
    sc.add_argument("--outdir", required=True)
    a = p.parse_args()
    try:
        import oroscope  # noqa: F401
    except ImportError:
        sys.exit(f"oroscope is not installed for {sys.executable}; install it with\n"
                 f"  {sys.executable} -m pip install oroscope\n"
                 f"or leave --python (and $OROSCOPE_PYTHON) unset to use the tools' own Python environment")
    {"plan": cmd_plan, "scan": cmd_scan}[a.cmd](a)


if __name__ == "__main__":
    main()
