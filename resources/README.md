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
├── geometry/                   site geometries (HDF5 + JLD2)
├── sites/                      atmosphere + geomagnetic field per site (TOML)
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

Self-contained site geometries. The main format consumed by the pipeline is `.jld2`, i.e. a Geometry `G` frame. The `.h5` file is the full precision source for this file. 

The CORSIKA executable `tambo_shower` requires PLY meshes for the terrain and observation surface; these are generated on demand by the CORSIKA input stage from the JLD2 bundle.

| File | Format | Consumer |
|---|---|---|
| `<site>.h5` | HDF5 | `build_gcd_bundle` (full-precision source) |
| `<site>_<resolution>.jld2` | JLD2 | TamboSim runtime (loaded directly via `load_frames`) |

The currently-shipped site is **Colca Valley**:
- `colca_valley.h5` — HDF5 source. Multiple resolutions are stored as
  named groups; the suffix is the radial-sample count, not the triangle
  count (e.g. `colca_valley_30000` is the 30 000-sample build, which
  meshes to 179 996 triangles).
- `colca_valley_3000.jld2` — pre-built test GCD bundle from the
  `colca_valley_3000` group, used as the default `--geometry` input for
  every template script.

To generate a new site, see [`examples/templates/1_create_geometry.jl`](../examples/templates/1_create_geometry.jl).

## `sites/`

One TOML file per observation site, giving the atmosphere layer profile and
the local geomagnetic field — the two location-dependent inputs to CORSIKA.
`[corsika] site_file` gives the path to one of these, or to a file of your own;
`tambo_shower` reads it via `--site-file`, so **adding or editing a site needs
no rebuild**. Any number of layers is supported.

| File | Purpose |
|---|---|
| `colca.toml` | TAMBO site, Colca Valley. Local radiosonde / reanalysis fit. |
| `lima.toml` | TAMBO-4 Lima validation site. ERA5 garua-season fit. |

The schema, unit conventions and the "how to add a site" notes are in
[`sites/README.md`](sites/README.md).

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
