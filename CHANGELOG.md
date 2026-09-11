# Changelog

Notable changes per release. Entries are written in the PR that makes the change,
and this file is the source for the GitHub release notes.

## 1.1.0 — 2026-09-10

### Breaking

- `[corsika] site_file` is now required with no default. Every existing CORSIKA
  config needs the key added; see `resources/sites/README.md`.

### Added

- **`MuonNeutrinoInjection` strategy** (#96) — routes ν_μ CC events straight to
  CORSIKA via the vertex muon, bypassing PROPOSAL decay. Uses the `CSMS_nutau`
  cross-section table for now (CSMS is flavor-independent).
- **Site-configurable atmosphere and geomagnetic field** (#102) — both were
  compiled into `tambo_shower`; they are now a TOML passed as `--site-file`. Ships
  `resources/sites/{colca,lima}.toml`, allows an arbitrary layer count, validates
  up front, and copies the resolved file to `<outdir>/site.toml`.

### Fixed

- **BVH SAH splits** — `find_best_split` indexed the global AABB table with
  node-local sort positions, so every node below the root scored its splits against
  unrelated triangles. Trees were correct but pruned badly. On a 50k-triangle mesh:
  build 1.06 s → 0.24 s, queries ~1.4× faster, identical hit sets.
- **TauRunner-absorbed leptons leaked into injection** — the `survived` flag was
  ignored, so muons that ranged out were still injected, up to thousands of km
  underground, producing CORSIKA jobs with zero hits. Affected ~76% of ν_μ muon
  jobs at 3e5 GeV, rising to ~96% at 1e9 GeV. ν_τ unaffected.
- **Units bug in `make_stopping_condition`** — `particle_rock_range` returns column
  depth, not length; now divided by `ROCK_DENSITY`.
- **`run_sbatch`** — argv is shell-escaped inside `--wrap` so arguments with spaces
  survive submission.
- Small cleanups: `AABB(indices, aabbs)` off-by-one, a no-op CDF clamp, a dead
  expression in `pl_norm`.

### Docs

- `resources/sites/README.md` documents the site schema and corrects the
  exponential-layer density formula — CORSIKA anchors every layer at sea level, not
  at the layer top. Shipped files are unaffected, but anyone writing a new site from
  the old formula would have been ~44% off.

## 1.0.1 — 2026-09-04

### Fixed

- Sign of the vertical geomagnetic field component, which was off by a factor of
  -1 (#101).

Note: `Project.toml` was not bumped for this release and still read `1.0.0`;
resynced in 1.1.0.

## 1.0.0 — 2026-05-22

The first versioned release, and a wholesale rewrite that replaces the pre-v1
codebase. Intentionally breaking: code, configs, and saved data from `v0.1.0-*`
are not compatible without changes.

### Added

- **Frame redesign** (#77) — G/C/D/M/Q/R Frame streams with parent-chain key
  inheritance, replacing the previous framework.
- **New weighting implementation** (#79) — `phase_space.jl` replaces
  `compute_weights.jl` / `weight_parameters.jl`: `oneweights` for `TamboFrames`
  (disjoint *and* overlapping simulation sets), `PhaseSpace` / `PhaseSpacePoint`
  density-dispatch structs, and `geometry_hash` for value-based G-frame comparison.
- **CORSIKA air showers through rock** (#90) — the new `tambo_shower` binary,
  replacing `corsika_cpp`, propagates showers through the terrain volume.
  Electron/photon propagation in rock is disabled (large speedup, no physics loss).
  Requires the `mesh-bvh-geometry-framework` branch of CORSIKA-8.
- **CORSIKA orchestration refactor** (#85) — `plan_corsika_jobs`,
  `build_corsika_argv`, pluggable executors (`run_local`, `run_sbatch`,
  `dump_to_file`, `collect_jobs`), and the symmetric `read_corsika_hits!`.
- **Cosmic-ray injection for any primary species** (#89) — no longer proton-only;
  select any nucleus by PDG code or `(A, Z)` pair.
- Reworked `examples/`, a CI-gated unit-test suite plus a `test/corsika_binary`
  integration suite, and startup version reporting (#78, #83, #86, #87, #92).

### Changed

- **Package renamed `Tambo` → `TamboSim`** (#92) — entry point is now
  `src/TamboSim.jl`. The UUID is preserved.

Full PR list: https://github.com/TAMBO-Observatory/TamboSim/releases/tag/v1.0.0
