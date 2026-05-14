# gcd-ply-storage branch — Changes Summary

**Branch:** `gcd-ply-storage` (off `v1-staging`).  
**Goal:** flip the JLD2/HDF5-PLY dependency so the GCD bundle (JLD2) is the
primary artifact and HDF5 + binary PLY files are derived outputs, not inputs.
Remove all file-format-based geometry loading from the library.

---

## 1. `build_gcd_bundle` — data-based signature

**File:** `src/geometry/earth.jl`

`build_gcd_bundle` previously accepted a `"file.h5:groupname"` path string and
read geometry from disk. It now accepts raw arrays:

```julia
build_gcd_bundle(
    vertices        :: Matrix{Float64},      # (n_verts, 3) ECEF metres
    faces           :: Matrix{<:Integer},    # (n_faces, 3) 1-based
    longlat_rad     :: NTuple{2,Float64},    # (lon, lat) in radians
    prem_radii      :: Vector{<:Unitful.Length},
    detector_region :: Vector{Int}           # 1-based face indices
) -> TamboFrames
```

The G frame now stores all raw inputs alongside the existing typed geometry
objects, so derived files can be regenerated from the bundle alone:

| Key | Type | Description |
|---|---|---|
| `"vertices"` | `Matrix{Float64}` | ECEF positions in metres |
| `"faces"` | `Matrix{Int}` | 1-based vertex indices |
| `"longlat_rad"` | `Vector{Float64}` | Site (lon, lat) in radians |
| `"prem_radii"` | `Vector{<:Unitful.Length}` | PREM layer radii |
| `"prem"` | `Vector{Sphere}` | Typed sphere layers (unchanged) |
| `"topography"` | `Vector{Triangle}` | Typed mesh (unchanged) |
| `"bvh"` | `BVHTree` | Acceleration structure (unchanged) |
| `"cs"` | `CoordinateSystem` | Local frame (unchanged) |
| `"geometry_hash"` | `UInt64` | SHA256-derived hash (unchanged) |

---

## 2. Removed geometry loaders

**File:** `src/geometry/earth.jl`

The following functions were removed entirely. Backward compatibility is not
provided.

| Removed | Reason |
|---|---|
| `_load_earth_h5` | HDF5 is now a derived output, not input |
| `_load_earth_ply` | ASCII PLY format no longer supported as input |
| `load_earth!` | Lazy-load pattern replaced by always-present JLD2 data |
| `_ensure_earth_loaded!` | No longer needed; callers updated |
| `_ensure_geometry_hash!` | Hash always present at bundle creation time |
| `injection_longlat` | Only used by the removed PLY loader |
| `parse_ply` / `parse_ply_header` | Only used by the removed PLY loader |
| `parse_triangles(HDF5.Group, ...)` | Only used by the removed HDF5 loader |

Call sites of `_ensure_earth_loaded!` were removed from:
- `src/injection/inject.jl`
- `src/julia_interfaces/proposal/propagation.jl`
- `src/corsika/run_corsika.jl`

The `_ensure_geometry_hash!` call site was removed from
`src/frames/io.jl:_reconstruct_frames`.

---

## 3. New export functions: `dump_to_h5`, `dump_to_ply`

**File:** `src/geometry/earth.jl`

Two new public functions write derived files from a loaded GCD bundle.

### `dump_to_h5`

```julia
dump_to_h5(g_frame, d_frame, path::String, groupname::String)
```

Writes the geometry from a GCD bundle to an HDF5 file under `groupname`,
using the same schema that the old `_load_earth_h5` expected:

```
<groupname>/location   — [lon_deg, lat_deg]
<groupname>/radii      — PREM radii in metres
<groupname>/vertices   — (n_verts, 3) ECEF metres
<groupname>/faces      — (n_faces, 3) 1-based indices
<groupname>/detector1  — 1-based detector face indices
```

### `dump_to_ply`

```julia
dump_to_ply(frame::Frame, fname::String;
            max_radius_km=nothing, watertight_depth=nothing)
```

Writes a binary-little-endian PLY file for CORSIKA's `tambo_shower`.

- **G frame:** writes the full terrain mesh. `max_radius_km` crops faces
  whose centroid exceeds that radius from the site centre. `watertight_depth`
  (metres) closes the mesh with `make_watertight` after any cropping.
- **D frame:** writes the detector-region (observation) mesh. Raw vertex/face
  data is read from the parent G frame via the frame hierarchy. The
  `max_radius_km` and `watertight_depth` kwargs are unused for D frames.

---

## 4. `make_watertight` migrated into the library

**File:** `src/geometry/earth.jl`

`make_watertight` was previously a local function in the example scripts. It
is now in the library and called by `dump_to_ply`.

```julia
make_watertight(vertices::Matrix{Float64}, faces::Matrix{Int};
                depth_m::Real=10_000.0) -> (vertices, faces)
```

Closes an open surface mesh by tracing the boundary loop, offsetting it
inward by `depth_m` metres along the radial direction, and adding side walls
and a bottom cap. Returns the inputs unchanged if the mesh is already closed.

---

## 5. `corsika_run` — PLY files derived from frames

**File:** `src/corsika/run_corsika.jl`

The frames-level `corsika_run` previously required `obs_mesh_path` and
`terrain_mesh_path` as config keys pointing to pre-generated PLY files on
disk. These keys are removed. Instead, the function generates the PLY files
from the G and D frames at call time and writes them to `base_outdir`:

```
<base_outdir>/obs_surface.ply   — always written, from D frame
<base_outdir>/terrain.ply       — written when use_terrain_mesh=true
```

**New config key:** `"use_terrain_mesh"` (Bool, default `true`).

**Cleanup:** when `parallelize=false` all jobs have completed synchronously,
so the PLY files are removed in a `finally` block. When `parallelize=true`
the sbatch jobs have not yet run when the submit loop returns, so the files
are left in place. The caller is responsible for cleaning up `base_outdir`
after all cluster jobs finish.

---

## 6. Example and internal script updates

### `examples/templates/1_create_geometry.jl`

- JLD2 is now written first (primary output).
- HDF5 and binary PLYs are written afterward via `TamboSim.dump_to_h5` and
  `TamboSim.dump_to_ply`.
- ASCII PLY (`write_geometry_ply`) removed entirely.
- Local helper functions `write_geometry_h5`, `write_corsika_ply`,
  `detector_subset` removed (now covered by library functions).

### `examples/templates/1_create_geometry_from_kml.jl`

Same restructuring: JLD2 first, derived outputs via library functions. Local
copies of `write_corsika_ply`, `make_watertight`, `detector_subset`, and
`write_geometry_h5` removed.

### `examples/_internal/rebuild_geometry_jld2.jl`

Updated to read raw arrays from HDF5 directly and call the new data-based
`build_gcd_bundle`, rather than passing a path string to the old API.

---

## 7. Tests

**New file:** `test/test_earth.jl` (60 tests, registered in `runtests.jl`).

| Testset | What is verified |
|---|---|
| `build_gcd_bundle` | G/D frame structure; raw arrays stored; JLD2 round-trip preserves all keys and `geometry_hash` |
| `make_watertight` | Already-closed mesh returned unchanged; open mesh gains zero boundary edges |
| `dump_to_h5` | HDF5 schema (all keys present, `location` in degrees); values round-trip exactly |
| `dump_to_ply` | PLY header format; G-frame vertex/face counts; `max_radius_km` reduces face count; D-frame produces exactly `length(detector_region)` faces; bad stream type raises error |

`HDF5` added to `test/Project.toml` deps to support direct HDF5 verification
in `dump_to_h5` tests.
