# TamboSim test suite

## Setup (once per clone)

```julia
using Pkg
Pkg.activate("test")
Pkg.instantiate()
```

The `[sources]` stanza in `test/Project.toml` resolves `TamboSim` from `..`, so no
manual `Pkg.develop` is needed.

## Running tests

**Full suite** (canonical, used by CI):

```julia
Pkg.test()                              # from the package's own env
Pkg.test(test_args=["Geometry"])        # filter to one or more testsets
```

**Selected testsets** (fast dev iteration — substring match, case-insensitive,
multiple patterns OK):

```bash
julia --project=test test/runtests.jl Geometry
julia --project=test test/runtests.jl Weighting "Detector Culling"
```

**Single file standalone** (each `test_*.jl` runs its own `run_*_tests()` when
invoked directly):

```bash
julia --project=test test/test_geometry.jl
```

## Adding a new testset

1. Define `run_mything_tests()` inside `test/test_mything.jl`, mirroring the
   header (`include("testsetup.jl")`) and footer (standalone-runner block) of
   the existing files.
2. Add an entry to the `TESTSETS` table at the top of `runtests.jl`.

Internal symbols imported from `TamboSim` belong in `test/testsetup.jl` so all
files share the same preamble.

## Runtime profile

Last measured 2026-05-09 by Kiara (branch `test-suite-fix`, Julia 1.12.4).
Full suite = **3m48s** / 4010 tests.

| Testset                    | Time   | Tests |
| -------------------------- | -----: | ----: |
| Injection Regression       | 2m04s  |  3078 |
| Propagation Decay Fraction |   54s  |     6 |
| Simulation API             |   31s  |    53 |
| CORSIKA                    |  5.7s  |   115 |
| Frames                     |  4.3s  |   154 |
| Geometry                   |  2.6s  |   126 |
| Sampler Statistics         |  2.4s  |    44 |
| Display                    |  1.2s  |    41 |
| Proton Injection           |  1.0s  |    11 |
| Particles                  |  0.6s  |    52 |
| _remaining 6 testsets_     | <0.5s  |     — |

Three testsets account for ~92% of runtime. Skipping
`Injection Regression`, `Propagation Decay Fraction`, and `Simulation API`
drops dev iteration to roughly the JIT/precompile floor (~20s on a warm
machine).
