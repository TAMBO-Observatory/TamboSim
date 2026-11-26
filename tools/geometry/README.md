# Geometry tools

Build TamboSim geometry bundles (the G/C/D frames consumed by `load_frames`) for any site
outlined in a KML or KMZ file — drawn in Google Earth (Pro or web), QGIS, etc. — or given as the
four corners of a box. Everything runs in the `tools/` environment:

```bash
JULIA_PKG_USE_CLI_GIT=true julia --project=tools -e 'using Pkg; Pkg.instantiate()'
```

TamboMakie (for `--view`) comes from the TAMBO-Observatory GitHub over SSH, branch `main`;
`JULIA_PKG_USE_CLI_GIT=true` lets Pkg clone it with your `git`/ssh-agent setup.

| Path | What it is |
|---|---|
| `create_geometry.jl` | New site: rotate a base triangulation onto the outline's centroid (KML or `--corners`), elevate it from a DEM, write `<name>.jld2` (G, C, D); optionally a `.h5` copy and CORSIKA PLYs |
| `src_jl/kml_outline.jl` | Functions only: the outline — from a KML/KMZ placemark or corner points; polygons with holes, area centroid |
| `src_jl/site_mesh.jl` | Functions only: rotate the base triangulation onto the site and apply DEM heights |
| `src_jl/copernicus_dem.jl` | Functions only: Copernicus GLO-30 tiles from AWS, or an HDF5 grid, as a bilinear interpolator |
| `src_jl/view_geometry.jl` | Functions only: the `--view` window (TamboMakie + GLMakie); loaded only when `--view` is given |
| `resources/triangulation.h5` | Base triangulations `base_triangulation_N` (65 MB; made by Kiara Carloni). `_100000` is the TAMBITO bundles' and `_30000` the TAMBO-4 one, both verified vertex for vertex against the official bundles |
| `resources/tambito_candidates_june23.kml` | TAMBITO candidate outlines, for `--kml`; placemark ids `final_candidate_areas.N` / `extra_sites.N` (West of Huambo = `final_candidate_areas.16`) |

## Usage

```bash
# your own outline: a KML/KMZ with one polygon needs no --placemark
julia --project=tools tools/geometry/create_geometry.jl --kml my_site.kmz --outdir out/

# a file with several placemarks: list them, then pick one by name, id or Comments
julia --project=tools tools/geometry/create_geometry.jl --kml sites.kml --list
julia --project=tools tools/geometry/create_geometry.jl --kml sites.kml --placemark "My site"

# no KML: four corners of a box as LAT LON pairs (degrees), in order around the box
julia --project=tools tools/geometry/create_geometry.jl \
    --corners -15.757 -72.123  -15.745 -72.138  -15.740 -72.134  -15.752 -72.119

# a TAMBITO candidate (the default --triangulation is resources/triangulation.h5:base_triangulation_100000)
julia --project=tools tools/geometry/create_geometry.jl \
    --kml tools/geometry/resources/tambito_candidates_june23.kml --placemark final_candidate_areas.16
```

The outline is required: pass either `--kml` or `--corners`. Files are written to the directory
the script is run from unless `--outdir` is given.

**Outputs.** By default only `<name>.jld2`, the G/C/D bundle, which is all the simulation
needs (`load_frames`, or `gc_path`/`d_path` in the pipeline). Two extras are opt-in:

- `--h5` writes `<name>.h5`: the same geometry as plain arrays (`location`, `radii`,
  `vertices`, `faces`, `detector1`; the `examples/templates/1_create_geometry.jl` schema), about
  4% of the `.jld2`'s size. JLD2 stores Julia type names, so a TamboSim change that renames or
  restructures a frame type can leave a `.jld2` unloadable; the `.h5` rebuilds it with
  `build_gcd_bundle` (as `examples/_internal/rebuild_geometry_jld2.jl` does). Worth keeping for
  geometries you will use long-term.
- `--ply` writes `<name>_terrain.ply` and `<name>_obs_surface.ply`, the CORSIKA meshes, for
  inspection in other tools. `run_corsika` writes its own from the `.jld2`.

**Viewing the result.** Add `--view` to open an interactive 3D window once the files are written,
as in TamboMakie's `examples/1_viz3D.jl`: the terrain around the site coloured by elevation
(a square 2.5× the outline's reach, at least 10 km), the detector region in blue, and detector
units if any. Drag to rotate and scroll to zoom; W/S A/D R/F move the camera, J/L I/K Q/E turn
it, B/N change the field of view. The script ends when the window is closed. This needs a
display; GLMakie and TamboMakie are loaded only for `--view`.

**Corners.** `--corners` takes exactly four latitude/longitude pairs — latitude first, unlike
KML's lon,lat — listed in order around the box, clockwise or anticlockwise; the box need not be
a rectangle. Corners listed diagonally (so the edges cross), repeated or lying on a line are
rejected, and a lon/lat mix-up is caught by the latitude check below. It cannot be combined with
`--kml`, `--placemark` or `--list`. Output files default to `box_<lat>_<lon>` of the centre.

**The outline.** A placemark is matched by its `<name>`, its `id` attribute, or a "Comments"
field (ExtendedData, including Google Earth web exports where the field is renamed but keeps
"Comments" as its display name). If several match and only one is a polygon (e.g. a pin and an
outline with the same name), the polygon is used. Its geometry must contain a Polygon; every
Polygon in it (a MultiGeometry) is part of the detector region. A KML polygon may also have
inner boundaries (`<innerBoundaryIs>`), i.e. cut-outs like the hole in a donut — e.g. to keep a
lake, road or village out of the array; triangles inside a cut-out are not detector region.
Google Earth Pro cannot draw these, but GIS tools (QGIS etc.) write them. Points and paths are
rejected. The site centre is the outline's area centroid.

**Checks.** The detector region must lie inside the triangulation's fine-mesh zone (10 km
from the centre for `triangulation.h5`; beyond it triangles are ~5× larger, ~300 m). If any
outline vertex is farther than that, the builder warns and asks `Continue anyway? [y/N]`
before doing any work; anything but `y` stops it, and so does running without interactive
input (batch jobs, stdin from `/dev/null`), unless `--allow-outside-fine-mesh` is given. After
meshing it reports the detector triangles that have a vertex beyond 10 km, the share of the
detector surface area they cover and their size, e.g.

    3651 of 202945 detector triangles (26.2% of the detector surface area, 129.917 km²) lie
    outside the fine-mesh zone (r < 10.0 km). Median edge there: 280.0 m, vs 65.0 m inside.

All warnings (also: outline past the 50 km ring or past `--terrain-radius-km`) are repeated in
a summary at the end of the run. The builder stops if no triangle centre falls inside the
outline (outline smaller than the triangles), and stops before any work for sites the DEM can't
serve: Copernicus tiles above 50° latitude, or a terrain circle crossing ±180°.

The `--ply` terrain mesh is the full closed mesh, which is also what `run_corsika` writes by default.
`dump_to_ply` with `max_radius_km` keeps faces by centroid distance and then adds a skirt; with a
radius near 50 km (the triangulation's ring edge, where long fan triangles join the far field)
the crop can leave pinch vertices that `make_watertight` rejects, depending on the terrain.

Copernicus tiles are downloaded from the public bucket `copernicus-dem-30m.s3.amazonaws.com`
into a temporary directory that is deleted after reading; pass `--tile-dir DIR` to keep and
reuse them. `--dem path.h5` uses a grid instead (`longitude`, `latitude`,
`elevation[n_lat, n_lon]`; GMT's n+1 cell-edge coordinates are converted to centres).

The builder's D frame holds the detector region (faces inside the outline) but no modules: place
them with `place_detector_units` (`examples/templates/2_create_detector.jl`); `spacing = 125 m`,
`max_slope_deg = 35°` reproduces the existing `d_125m_large.jld2` layouts on their original terrain.

## How a mesh is made

Triangle sizes come only from the base triangulation, never from the terrain. Each
`base_triangulation_N` in `resources/triangulation.h5` holds 3N vertices (lon, lat in degrees around the
north pole) and 6N − 4 faces of a closed sphere: N points drawn uniformly at random in each of
three zones — a cap out to 10 km, a ring from 10 to 50 km, and the rest of the globe — joined
by GMT `sphtriangulate` (spherical Delaunay). The builder rotates the pole onto the site.

So resolution does not refine smoothly toward the site: it is constant inside each zone and
jumps at 10 km and 50 km (zone radii set with R = 6378 km, i.e. 9.99 and 49.95 km on the
6371 km sphere). Equal counts per zone give areal densities 1 : 1/24 : 1/1.6·10⁶, so spacing
grows ×4.9 at 10 km and ×1270 at 50 km. Because points are random rather than on a lattice,
edges within a zone span about a factor 7 (5–95 %) and include slivers. Measured median edge
lengths (5–95 % for the cap):

| Group | Used by | 0–10 km | 10–50 km | > 50 km |
|---|---|---|---|---|
| `base_triangulation_1000` | | 603 m (168–1241) | 2.96 km | 774 km |
| `base_triangulation_3000` | | 352 m (101–678) | 1.72 km | 445 km |
| `base_triangulation_10000` | | 191 m (55–377) | 934 m | 243 km |
| `base_triangulation_30000` | TAMBO-4 (Lima) | 111 m (31–219) | 543 m | 141 km |
| `base_triangulation_100000` | TAMBITO sites | 60 m (17–119) | 296 m | 77 km |
| `base_triangulation_300000` | | 35 m (10–69) | 171 m | 45 km |

Beyond 50 km there is effectively no terrain: for `_100000` the ring's edge is joined to the
first ~10 outer vertices (63–160 km out) by ~230 long, thin fan triangles. With the default
50 km terrain radius those outer vertices sit at 0 m, so the fans ramp down from the local
altitude to sea level in every direction; a larger `--terrain-radius-km` gives them real heights.
Within each zone the triangles are statistically alike but individually irregular (Delaunay of
random points): median smallest angle 31°, 6 % below 10°. The file also holds
`colca_valley_N` groups: the same triangulations already elevated for the Colca valley site, with
detector regions, in the `1_create_geometry.jl` HDF5 schema.

The DEM only sets vertex heights: vertices within `--terrain-radius-km` (great-circle distance
from the centre; 50 km by default, the ring's edge) are moved to `R + h(lon, lat)` with `h`
sampled bilinearly from the grid, the rest stay on the 6371 km sphere at 0 m. (Bundles built
before 2026-11 used a lon/lat box of ±1.5·m by ±m, m = radius/111·1.5, inherited from the
spline's rectangular DEM crop: ~±110 km E–W by ±75 km N–S at the TAMBITO sites, so a few
far-field vertices in its corners got heights and the rest did not.) The simulation sees
the flat triangles between vertices; there is no spline in the bundle. With Copernicus the
60 m triangles, not the DEM, limit the fidelity near the array: they fill gullies and clip
ridges narrower than ~100 m. Bilinear point sampling beat box means sized to the local
spacing both near the array (5.4 vs 5.9 m robust σ vs a drone survey) and in the 10–50 km ring
(24.6 vs 29.9 m vs full-resolution Copernicus).

## DEM choice: Copernicus GLO-30

| | Copernicus GLO-30 | SRTM15+ (GMT `earth_relief_15s`) |
|---|---|---|
| Source | TanDEM-X InSAR 2011–15, edited | SRTM-CGIAR (2000) on land, resampled; soundings + altimetry at sea |
| Grid | 1″ ≈ 30 m, EGM2008 | 15″ ≈ 460 m |
| vs drone survey, west of Huambo (robust σ) | 3.0 m | 45.6 m (cell centres) |
| vs ALOS AW3D30, Lima (robust σ) | 2.3 m | 22.4 m |
| Registration vs drone / AW3D30 | < 0.1″ | 1–2″ NE even with cell centres |
| Median slope, west of Huambo (drone: 30°) | 28° | 18° |
| Sea | 0 m (flat) | bathymetry |

Copernicus is a surface model (buildings, vegetation) — irrelevant on the Andean sites,
visible as metre-scale structure in Lima. SRTM15+ is only preferable if sea-floor depth matters.

## History: bundles built before 2026-11

The earlier builder, `create_geometry_from_kml.jl` (used for `tambito_sites/*` and
`prototypes/TAMBO-4`), read SRTM15+ from an HDF5 written by GMT.jl. GMT.jl returns n+1 cell
edges for pixel-registered grids (`range(west, east, length = nx + registration)`); the
script kept the first n, putting every 15″ cell at its SW corner. Together with SRTM15+'s own
1.4–1.8″ offset, all terrain was drawn ≈ 6″ (≈ 180 m S and 175 m W, ~250 m) from its true
position, uniformly over the whole mesh, and smoothed to ~500 m. Rebuilding with the script's
recipe reproduces the official west_of_huambo vertex heights to < 1 mm.

At west of Huambo (drone survey, 115 modules): drone − mesh robust σ 68 m → 31 m with the shift
undone → 5.4 m with Copernicus; median slope 16° → 26° (drone 30°); modules more than 50 m from
the real ground 69 → 0. The site centroid also averaged in the KML ring's closing vertex,
moving the origin ~220 m toward the first vertex, so new builds of an existing site have a
slightly different origin and local frame than the old bundles.
