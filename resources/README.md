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
| `tau_neutrino_cc_fine_ecut.toml` | Same physics with tighter PROPOSAL energy cuts; slower but more accurate for low-energy lepton tracking. |

Path entries inside these configs use the `_TAMBOSIM_PATH_` placeholder
to refer to the package root. `Tambo.relativize!(config)` substitutes
that placeholder (and resolves bare relative paths) at load time.

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
- `colca_valley.h5` — HDF5 source, multiple resolutions stored as named
  groups (e.g. `colca_valley_30000` for the 30 000-triangle mesh).
- `colca_valley_3000.jld2` — pre-built GCD bundle at 3 000 triangles,
  used as the default `--geometry` input for every template script.
- `colca_valley_terrain.ply` and `colca_valley_obs_surface.ply` — the
  CORSIKA-side meshes for the 30 000-triangle build.

To add a new site, run `examples/templates/1_create_geometry.jl` (on
the `kiara_examples_overhaul` branch — these will move under
`examples/templates/` once that branch lands).

## `cross_section_tables/`

`cross_sections.h5` — neutrino-nucleon CC cross-section tables (CSMS),
loaded by `Tambo.CrossSection` for use during injection. Indexed by
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
