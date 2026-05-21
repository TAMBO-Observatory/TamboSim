# tambo_shower test suite

Automated tests for the `tambo_shower` CORSIKA 8 binary — the TAMBO
air-shower driver (`src/corsika/tambo_shower/`). The binary is the physics
core of the air shower simulation, and is not tested by the Julia test suite:
`test/test_run_corsika.jl` and `test/test_read_corsika.jl` exercise the
Julia orchestration and the parquet readers, but never the binary itself.

Each test runs real CORSIKA showers, so the suite runs on a cluster (FASRC)
as a single Slurm job — not in local CI.

## Running

The test suite can be run (on Harvard's FAS research computing server) via:
```
sbatch test/corsika_binary/submit.slurm
```

This shell script contains five phases, run by the numbered scripts:

| Phase | Script | What it does |
|-------|--------|--------------|
| 0 — geometry | `0_make_geometry.jl` | if needed, builds the canonical GCD bundle from the committed `resources/geometry/colca_valley.h5` |
| 1 — plan | `1_plan.jl` | checks prerequisites, injects primaries, plans CORSIKA jobs → `jobs.jsonl`, saves injected frames → `injection.jld2` |
| 2 — CLI | `2_cli_tests.sh` | CLI argument-contract checks (no showers run) |
| 3 — run | `3_run_showers.sh` | replays every planned shower, in parallel (`xargs -P`) |
| 4 — assert | `4_assert.jl` | the physics / geometry checks over the output |

The unnumbered files are not part of the sequence: `submit.slurm` is the
launcher, `assertions.jl` is the check library that `4_assert.jl` includes,
and `make_baselines.jl`, `calibrate_muon_survival.jl`, and `timing_overview.jl`
are occasional tools (see below).

The Slurm job exits non-zero — and is marked FAILED — if the CLI checks or
any assertion fails.

## Prerequisites

- **The binary.** Build `tambo_shower` per `src/corsika/tambo_shower/src/README.md`;
  the suite expects it at `src/corsika/tambo_shower/src/build/tambo_shower`, and
  it must be built `WITH_FLUKA`.
- **PROPOSAL interpolation tables.** Two separate sets: the Julia side (tau
  propagation during neutrino injection, `TAMBO_PROPOSAL_TABLES`) and the
  binary side (`$CORSIKA_DATA/PROPOSAL`). `1_plan.jl` fails fast with a clear
  message if either is missing, rather than letting a run silently spend hours
  rebuilding them.
- **`julia` and `jq`** on `PATH`.

Paths are set in the **SITE CONFIGURATION** block at the top of `submit.slurm`
— review them for your environment. Each can also be overridden by exporting
the variable before `sbatch`.

## What's tested

Five configs (`configs/*.toml`):

| Config | Primary | Energy | Geometry | Showers |
|--------|---------|--------|----------|---------|
| `cr_proton_vertical` | proton | 10 TeV | near-vertical downgoing | 5 |
| `cr_proton_vertical_crop` | proton | 10 TeV | near-vertical, terrain crop | 5 |
| `cr_muon_skimming` | muon | 10 TeV | grazing fuzzer (azimuth 150–210°) | 8 |
| `cr_muon_skimming_100TeV` | muon | 100 TeV | grazing, terrain crop | 2 |
| `nu_tau_injection` | ν_τ → τ → shower | 100 TeV | 65–125° | ≤ 20 |

Phase 2 checks the **CLI contract**: malformed invocations are rejected and
`--help` exits zero — no showers are run.

Phase 4 runs the checks in `assertions.jl` over every shower's output. Each
check self-gates — it asserts nothing on a shower it is not relevant for, so
all checks run against all showers:

- **Output tree.** The expected directory tree, every parquet present and
  readable, the binary exited 0.
- **Injection round-trip.** The particle the suite injected matches the
  particle CORSIKA ran — pdg, energy, injection position, and direction —
  checked both against the argv the suite built and against CORSIKA's
  `primary/summary.yaml` echo, all in ECEF metres.
- **Energy budget.** Loose energy-budget inequalities: neither the integrated
  dE/dx loss nor the energy reaching the observation mesh exceeds the primary
  energy. CORSIKA keeps no global energy bookkeeper, so the bar is "nothing
  exceeds the primary", not strict closure.
- **Rock propagation — muons.** For a cosmic-ray muon that crosses the terrain
  rock, a PROPOSAL-calibrated survival probability decides whether the muon
  must reach the observation mesh (P > 99%) or must have lost all its energy
  in the rock (P < 1%); the stochastic regime in between is not asserted. A
  muon predicted to range out legitimately leaves an empty `particles.parquet`,
  so the energy-budget "something reached the mesh" check is waived for it.
  See "Muon survival calibration" below.
- **Rock propagation — EM primaries.** A π⁰ or e± injected inside the terrain
  rock develops no shower at all — the binary's `RockEMAbsorber` discards the
  EM cascade — so its longitudinal profile must be all zeroes.
- **Downgoing shower morphology.** A steeply downgoing (travel zenith > 130°)
  cosmic-ray proton shower is photon-dominated at the ground: most particles
  crossing the observation mesh are photons.
- **Log warnings.** The shower log carries no WARN/ERROR/CRITICAL line beyond
  a curated benign allowlist — catching the non-fatal warnings tambo_shower
  and CORSIKA can emit (a near-tangent rock exit, an obs/terrain mesh
  mismatch, a tracker/medium node disagreement) that would otherwise leave a
  complete-looking but wrong output.
- **Determinism** (per config). A shower rerun with the same seed and binary
  produces identical output.
- **Statistical consistency** (per config, opt-in). Median summary statistics
  stay within tolerance of a committed baseline. Statistical only — CORSIKA's
  depth-first stack makes bit-identical output across binary changes
  impossible. Only configs with enough well-developed showers for a stable
  median are baselined; the check is inactive for the rest. See "Refreshing
  the statistical-consistency baseline".

## Reading a failure

The Slurm log (`tambo_shower_test_<jobid>.log`) ends with a `@testset` summary
naming the failed check and config. To dig into one shower, under
`test/corsika_binary/out/<config>/event_*/shower_*` (or wherever
`$TAMBO_TEST_OUTDIR` points):

- `<outdir>.log` — the binary's full stdout/stderr for that shower.
- `<outdir>.rc`  — its exit code.

Both are siblings of the shower's output directory (so `--force` cannot wipe
them).

## Timing

`submit.slurm` prints a timing overview after Phase 4 — per-config and total
CORSIKA runtime (from each shower's `summary.yaml`), an estimated wall-clock at
the configured parallelism, and the slowest individual showers. To regenerate
it for an existing run:

```
julia test/corsika_binary/timing_overview.jl
```

with `TAMBO_TEST_OUTDIR` pointing at that run's output. Use it to check the
suite fits its runtime budget and to see which configs to trim.

## Refreshing the statistical-consistency baseline

A median over a handful of showers tracks shower-to-shower fluctuation, not a
physics regression, so only configs with enough well-developed showers are
baselined. A config opts in with `baseline = true` in its `configs/*.toml`
(currently the two `cr_proton_vertical*` configs); `make_baselines.jl` writes
a baseline for those alone, and `assert_statistical_consistency` skips the
comparison unless both the baseline and the fresh run cleared
`MIN_BASELINE_SHOWERS` contributing showers (`assertions.jl`).

To create the baselines from a run you trust:

```
julia test/corsika_binary/make_baselines.jl
```

with `TAMBO_TEST_OUTDIR` pointing at that run's output, then commit the
resulting `baselines/*.toml`. Regenerate them deliberately — only when a binary
change is understood and accepted, never to paper over an unexplained shift.

## Muon survival calibration

The muon rock-propagation check needs `calibration/muon_survival.toml` — the probability
that a muon of a given energy survives a given column depth of standard rock.
It is produced once, by Monte Carlo, with PROPOSAL (the same muon-transport
code `tambo_shower` uses in rock):

```
julia test/corsika_binary/calibrate_muon_survival.jl
```

with `TAMBO_PROPOSAL_TABLES` set. Commit the resulting
`calibration/muon_survival.toml`. Re-run only if the muon energies in the
configs change, or PROPOSAL is updated. Without the table the suite still runs
— the muon survive/die assertions are simply skipped.

<!-- 
## Known limitations / TODO

- The binary-side PROPOSAL tables are not yet in a shared location; each user
  points `CORSIKA_DATA` at their own copy. Worth copying a canonical set into
  `TAMBO/common_software` so the suite needs no per-user table build.
- Statistical-consistency tolerances (`rtol` in `assertions.jl`) are loose
  placeholders — tune them once the run-to-run baseline scatter is known. -->
