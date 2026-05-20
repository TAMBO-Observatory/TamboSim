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
sbatch test/corsika_fasrc/submit.slurm
```

This shell script contains five phases, run by the numbered scripts:

| Phase | Script | What it does |
|-------|--------|--------------|
| 0 — geometry | `0_make_geometry.jl` | if needed, builds the canonical GCD bundle from the committed `resources/geometry/colca_valley.h5` |
| 1 — plan | `1_plan.jl` | checks prerequisites, injects primaries, plans CORSIKA jobs → `jobs.jsonl` |
| 2 — CLI | `2_cli_tests.sh` | CLI argument-contract checks — the Tier 0 checks (no showers run) |
| 3 — run | `3_run_showers.sh` | replays every planned shower, in parallel (`xargs -P`) |
| 4 — assert | `4_assert.jl` | the tiered physics / geometry checks (Tiers 1–4) over the output |

The unnumbered files are not part of the sequence: `submit.slurm` is the
launcher, `assertions.jl` is the check library that `4_assert.jl` includes,
and `make_baselines.jl`, `calibrate_muon_survival.jl`, and `timing_overview.jl`
are occasional tools (see below).

The Slurm job exits non-zero — and is marked FAILED — if the Tier 0 checks
or any Tier 1–4 assertion fails.

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
| `cr_proton_vertical` | proton | 10 TeV | near-vertical downgoing | 3 |
| `cr_proton_vertical_crop` | proton | 10 TeV | near-vertical, terrain crop | 3 |
| `cr_muon_skimming` | muon | 10 TeV | grazing fuzzer (zenith 90–105°, azimuth 120–240°) | 8 |
| `cr_muon_skimming_100TeV` | muon | 100 TeV | grazing, terrain crop | 2 |
| `nu_tau_injection` | ν_τ → τ → shower | 100 TeV | 65–125° | ≤ 8 |

Tiers (`assertions.jl`) — the taxonomy of checks, distinct from the run
phases above:

- **Tier 0 — CLI contract.** Malformed invocations are rejected; `--help` works.
- **Tier 1 — smoke.** Expected output tree, parquet files present and readable,
  binary exited 0.
- **Tier 2 — physics sanity.** A developed longitudinal profile, well-formed
  observation-mesh particles (normalized directions, positive energies), and
  loose energy-budget inequalities (CORSIKA keeps no global energy bookkeeper,
  so the assertion is "nothing exceeds the primary energy", not strict closure).
  For a muon primary that crosses the terrain rock, this is gated on a
  **rock-traversal prediction**: the trajectory is ray-cast for its rock column
  depth, and a PROPOSAL-calibrated survival probability decides whether the muon
  must reach the observation mesh (P > 99%), must range out in the rock
  (P < 1%), or is in the stochastic regime (not asserted). A muon predicted to
  range out legitimately leaves an empty `particles.parquet`, so the
  "something reached the mesh" assertions are waived for it. See "Muon survival
  calibration" below.
- **Tier 3 — terrain / rock-air boundary.** No `RockInterfaceTripwire` abort,
  no obs/terrain mesh mismatch — regresses the CORSIKA-tracker-vs-mesh edge
  cases the bespoke rock-handling code exists to fix.
- **Tier 4a — same-build determinism.** A shower rerun with the same seed and
  binary produces identical output.
- **Tier 4b — cross-build regression.** Median summary statistics stay within
  tolerance of a committed baseline. Statistical only — CORSIKA's depth-first
  stack makes bit-identical output across binary changes impossible. Inactive
  until a baseline exists (see below).

## Reading a failure

The Slurm log (`tambo_shower_test_<jobid>.log`) ends with a `@testset` summary
naming the failed tier and config. To dig into one shower, under
`test/corsika_fasrc/out/<config>/event_*/shower_*` (or wherever
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
julia test/corsika_fasrc/timing_overview.jl
```

with `TAMBO_TEST_OUTDIR` pointing at that run's output. Use it to check the
suite fits its runtime budget and to see which configs to trim.

## Refreshing the Tier 4b baseline

Tier 4b is skipped until `baselines/<config>.toml` exists. To create the
baseline from a run you trust:

```
julia test/corsika_fasrc/make_baselines.jl
```

with `TAMBO_TEST_OUTDIR` pointing at that run's output, then commit the
resulting `baselines/*.toml`. Regenerate them deliberately — only when a binary
change is understood and accepted, never to paper over an unexplained shift.

## Muon survival calibration

The Tier 2 muon check needs `calibration/muon_survival.toml` — the probability
that a muon of a given energy survives a given column depth of standard rock.
It is produced once, by Monte Carlo, with PROPOSAL (the same muon-transport
code `tambo_shower` uses in rock):

```
julia test/corsika_fasrc/calibrate_muon_survival.jl
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
- Tier 4b tolerances (`rtol` in `assertions.jl`) are loose placeholders — tune
  them once the run-to-run baseline scatter is known. -->
