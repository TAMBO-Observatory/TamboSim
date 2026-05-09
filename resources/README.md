# TamboSim resources

Static input data the package needs at runtime — geometry meshes,
cross-section tables, configuration examples, and the PROPOSAL energy-
loss tables. Most of these are committed to the repo; the only
exception is `proposal_tables/`, which is generated on first use and
gitignored.

## Layout

```
resources/
├── configuration_examples/     example TOML configs
├── geometry/                   site geometries (HDF5 + PLY + JLD2)
├── cross_section_tables/       neutrino-nucleon xsec tables
└── proposal_tables/            PROPOSAL energy-loss tables (gitignored)
```

## `configuration_examples/`

Hand-edited TOML files that drive the four pipeline stages
(`[injection]`, `[proposal]`, `[corsika]`, plus `[geometry]` for the
input bundle). Every other example or template that takes a `--config`
argument defaults to one of these.

| File | Purpose |
|---|---|
| `tau_neutrino_cc.toml` | The standard nu_tau CC configuration for the Colca Valley site, used for the TAMBO sensitivity paper. |
| `cosmic_ray_proton.toml` | Cosmic-ray proton injection variant; sets `strategy = "CosmicRayInjection"` so `inject!` dispatches to the proton backend. Pass to `templates/3_inject.jl` via `--config`. |

The shipped CORSIKA energy cuts (`hadron_ecut` ≈ 0.05 GeV, `em_ecut` /
`photon_ecut` ≈ 0.001 GeV) produce more complete shower particle lists
at higher computational cost. For fast test runs, raising every CORSIKA
`*_ecut` to ~1 GeV cuts shower-generation time substantially at the
price of fewer low-energy particles.

Path entries inside these configs use placeholders that
`TamboSim.relativize!(config)` substitutes at load time:

- `_TAMBOSIM_PATH_` — the TamboSim package root.
- `_TAMBO_DATA_PATH_`, `_TAMBO_CORSIKA_PATH_`, `_TAMBO_FLUPRO_PATH_` —
  values of the corresponding `TAMBO_DATA_PATH` / `TAMBO_CORSIKA_PATH` /
  `TAMBO_FLUPRO_PATH` environment variables, used by OSG production
  configs to defer cluster-specific paths to runtime.

`relativize!` also resolves bare relative paths against the package
root.

## `geometry/`

Self-contained site geometries. Each site exists in three formats
because different parts of the pipeline consume different ones:

| File | Format | Consumer |
|---|---|---|
| `<site>.h5` | HDF5 | `build_gcd_bundle` (full-precision source) |
| `<site>_terrain.ply` | binary PLY | CORSIKA 8 (`tambo_shower`) |
| `<site>_obs_surface.ply` | binary PLY | CORSIKA 8 observation mesh |
| `<site>_<resolution>.jld2` | JLD2 | TamboSim runtime (loaded directly via `load_frames`) |

The currently-shipped site is **Colca Valley**:
- `colca_valley.h5` — HDF5 source. Multiple resolutions are stored as
  named groups; the suffix is the radial-sample count, not the triangle
  count (e.g. `colca_valley_30000` is the 30 000-sample build, which
  meshes to 179 996 triangles).
- `colca_valley_3000.jld2` — pre-built GCD bundle from the
  `colca_valley_3000` group, used as the default `--geometry` input for
  every template script.
- `colca_valley_terrain.ply` and `colca_valley_obs_surface.ply` — the
  CORSIKA-side meshes built from the `colca_valley_30000` group.

To add a new site, run [`examples/templates/1_create_geometry.jl`](../examples/templates/1_create_geometry.jl).

## `cross_section_tables/`

`cross_sections.h5` — neutrino-nucleon CC cross-section tables (CSMS),
loaded by `TamboSim.CrossSection` for use during injection. Indexed by
PDG via group names like `CSMS_nutau`, `CSMS_numu`, etc.

## `proposal_tables/`

PROPOSAL caches its interpolated energy-loss tables here on first use.
Roughly 1 200 small files; can run into the hundreds of megabytes once
fully populated. Gitignored (`*.json` and `*.dat` patterns) — first run
on a fresh checkout takes several minutes while these get written, and
subsequent runs reuse them. Safe to delete if the directory grows
unwieldy; PROPOSAL will rebuild what it needs.

The path passed to PROPOSAL via the `[proposal] tablespath` config key
must point here.
