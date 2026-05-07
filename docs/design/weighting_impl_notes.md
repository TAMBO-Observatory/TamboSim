# Weighting refactor — implementation notes

**Branch:** `weights-refactor-impl`
**Date:** 2026-05-07
**Status:** partial — types, functors, and public API implemented; injection loop not yet wired.

This document records the decisions made during implementation and how they relate to the original design proposal (`weighting.md`).

---

## 1. Decisions that follow the proposal exactly

- **Abstract type hierarchy.** `PhaseSpace` and `PhaseSpacePoint` are declared as proposed. All five concrete types (`NeutrinoInjectionPS`, `ForcedNeutrinoInteractionPoint`, `UpstreamNeutrinoInteractionPoint`, `CosmicRayInjectionPS`, `SurfaceCRPoint`) are implemented.

- **Multiple dispatch for PS/Point compatibility.** Incompatible combinations (e.g. `CosmicRayInjectionPS` called with a `ForcedNeutrinoInteractionPoint`) return zero via a fallback method rather than crashing. A `@warn` is emitted from the fallback because hitting it in practice indicates a wiring bug.

- **`oneweight` public API.** `oneweight(tf, q)` and `oneweights(tf)` are implemented as specified, returning `GeV·m²·sr`. `oneweights!` was added as a convenience that writes the result directly onto each Q frame under a configurable key (default `"oneweight"`).

- **`build_phase_space` factory.** Reads the M frame's injection config dict and constructs the appropriate PS subtype. Discriminates neutrino vs cosmic-ray campaigns by the presence of `"xs_location"` in the config. Accepts an optional `prefix` argument (default `"injection"`) matching the injection loop's convention.

- **`p_phys` kept but marked for `@doc false`.** Retained as an internal helper; the functor for `ForcedNeutrinoInteractionPoint` calls it directly. Not yet marked `@doc false` — deferred to cleanup pass.

- **Null/failed events.** `oneweight` returns `0.0u"GeV*m^2*sr"` with a warning when `q["phase_space_point"]` is absent, keeping the output vector aligned with `tf`.

- **Serialization.** `PhaseSpacePoint` structs are stored directly as JLD2 typed structs. `PhaseSpace` functors are regenerated on the fly via `build_phase_space` from the M frame's config dict. This matches the proposal's rationale: PS structs are cheap to reconstruct and avoiding serializing them insulates old output files from struct renames.

---

## 2. Decisions that deviate from or extend the proposal

### 2.1 Field split: `area`, `cd`, `rho`, `sigma`, `dsigma` are per-event

The proposal showed `area` in `NeutrinoInjectionPS` (campaign-level). After reading the injection loop, we confirmed that `area = sum(visible_areas)` is recomputed for each sampled direction and therefore varies event-by-event. Similarly, `cd`, `rho`, `sigma`, and `dsigma` are computed per forced-CC interaction. All five fields were moved to the Point structs.

### 2.2 Geometry compatibility via hash, not object identity

The proposal did not specify how to check that a PS and a PhaseSpacePoint come from compatible detector geometries. The naive approach (`ps.g_frame !== pt.g_frame`) is a reference check that breaks when two separately loaded JLD2 files describe the same geometry.

The implemented approach:
- A `_geometry_hash` helper computes `hash(coords)` over a flat `Vector{Float64}` of raw vertex coordinates (PREM radii + topography vertex positions), avoiding Julia's struct-level `hash` which may use `objectid` for non-isbits types.
- The hash is stored as `g_frame["geometry_hash"]` at construction time in `build_gcd_bundle` and recomputed (with a mismatch warning) in `load_earth!`.
- `_compatible` compares the integer hash values. Two G frames loaded from the same geometry file will match regardless of whether they are the same Julia object.
- Mismatches warn rather than error, because hash collisions are negligible in practice and a hard error would be disruptive for legitimate near-miss cases (e.g. between-version hash algorithm changes).

### 2.3 `_compatible` checks phase-space bounds

Beyond geometry and PDG, `_compatible` checks that the event's energy, theta, and phi fall within the campaign's sampled range. This implements the "out-of-support returns zero" behavior described in the proposal without requiring explicit phase-space containment logic inside `oneweight` itself.

### 2.4 Vectorized API precomputes functors once

`oneweights` and `oneweights!` build `[build_phase_space(m) for m in tf.m_frames]` once before iterating over Q frames. `oneweight(tf, q)` rebuilds them per call — appropriate for single-event interactive use. The shared inner logic lives in `_oneweight_from_ps(q, phase_spaces)`.

### 2.5 Units: functors return `GeV^-1 * m^-2 * sr^-1`

Each functor returns the per-event contribution to the inverse one-weight in `GeV^-1 * m^-2 * sr^-1` (via `uconvert`). `oneweight` inverts the weighted sum and converts to `GeV * m^2 * sr`. This makes the units explicit at every layer and avoids ambiguity when mixing campaigns.

---

## 3. What remains

- **Injection loop.** `inject!` and `inject_protons!` need to construct the appropriate `PhaseSpacePoint` and write it to `q["phase_space_point"]`. This is the only step that makes the end-to-end API usable.
- **Round-trip injection test.** A test that runs a small injection and verifies `oneweights(tf)` matches the old inline formula applied to `weight_params`.
- **Cleanup.** Mark `p_mc`, `p_mc_surface`, `p_phys` as `@doc false`. Update inline formulas in `examples/` to call `oneweight`.

---

## 4. Tests

All new tests live in `test/test_weighting.jl` under `run_weighting_tests()`.

### 4.1 PhaseSpace functors (8 tests)

**`test_forced_neutrino_functor_matches_old_formula`**
Constructs a `NeutrinoInjectionPS` and `ForcedNeutrinoInteractionPoint` with known values, calls the functor, and checks the result matches `p_mc(wp) / p_phys(wp)` computed independently. Catches regressions in the forced-CC weight formula and unit conversion errors.

**`test_upstream_neutrino_functor_matches_old_formula`**
Constructs a `NeutrinoInjectionPS` and `UpstreamNeutrinoInteractionPoint`, calls the functor, and checks the result matches `p_mc_surface(wp)`. Catches regressions in the surface pdf formula for upstream-converted events.

**`test_cr_functor_matches_old_formula`**
Same as above for `CosmicRayInjectionPS` + `SurfaceCRPoint`. Confirms the CR and upstream-neutrino surface cases produce identical math (they share `_surface_pdf`).

**`test_compatibility_pdg_mismatch`**
Calls a CR phase space with a point whose PDG code does not match. Verifies the result is exactly zero. Catches bugs where PDG filtering is skipped or compared incorrectly.

**`test_compatibility_geometry_mismatch`**
Calls a CR phase space built from G frame with hash `1` against a point from G frame with hash `2`. Verifies zero. Catches bugs where the geometry check is missing or uses reference equality instead of hash equality.

**`test_compatibility_energy_out_of_bounds`**
Calls a CR phase space with `emin=1e3, emax=1e5` against a point with `E=1e6`. Verifies zero. Catches off-by-one or wrong-direction bound checks.

*(Three additional tests in this group cover the positive path for each functor type — verified nonzero, finite, correct sign.)*

### 4.2 Multi-campaign oneweight (6 tests)

**`test_disjoint_phase_spaces`**
Creates two `CosmicRayInjectionPS` with non-overlapping energy ranges (`[1e3, 1e5]` and `[1e5, 1e7]`). Checks:
- An event at `E=1e4` (in PS1 only): combined oneweight equals single-PS1 oneweight.
- An event at `E=1e6` (in PS2 only): combined oneweight equals single-PS2 oneweight.

Catches bugs where an out-of-support campaign incorrectly contributes to the sum, which would lower oneweights for all events.

**`test_overlapping_phase_spaces`**
Creates two `CosmicRayInjectionPS` with overlapping ranges (`[1e3, 1e6]` and `[1e5, 1e7]`). Checks:
- An event at `E=1e4` (PS1 only): combined oneweight matches single-PS1.
- An event at `E=5e5` (in overlap): combined oneweight is strictly less than either single-campaign oneweight.
- The exact value: `1 / (ps1(pt)*n1 + ps2(pt)*n2)` matches `_oneweight_from_ps`.

This is the core correctness test for the multiple importance sampling formula. It catches: wrong sign in the sum, missing `nevent` scaling, failure to accumulate contributions from multiple campaigns, and any branch that accidentally returns early before all campaigns are summed.
