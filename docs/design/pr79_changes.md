# PR #79 — Changes Applied During Review

Branch: `weights-refactor-impl`

The following changes were made while working through the review in `pr79_review.md`.
Items 3 (particle_passes_through_rock), 6 (fallback @warn rate-limiting), 8 (forced-CC
comment), and 11 (migration guide) were deliberately skipped — documentation overhead
not worth it at this stage with two developers.

---

## 1. Stable geometry hash (must fix)

**Files:** `src/geometry/earth.jl`, `src/TamboSim.jl`, `Project.toml`

Replaced `hash(coords)` in `_geometry_hash` with SHA256 over the raw IEEE 754 bytes of
the coordinate vector. Julia's built-in `hash()` is not stable across minor versions
(changed in 1.6→1.7 and again in 1.9), which would cause `_validate_geometry_hash!` to
throw on every `load_frames` call after a Julia upgrade.

`SHA` is a Julia stdlib — no new package dependency, but it does need to be declared in
`Project.toml [deps]` (added: `SHA = "ea8e919c-243c-51af-8825-aaa63cd721ce"`).

**Side effect:** any committed geometry JLD2 written with the old `hash()` will have a
different stored `geometry_hash` than what the new function computes. All geometry
bundles under `resources/geometry/` need to be regenerated after merging.

---

## 2. Proton injection altitude pinned in config (must fix)

**File:** `resources/configuration_examples/cosmic_ray_proton.toml`

Changed `altitude = 50.0` to `altitude = 112.0` (km) to match the code default that was
silently updated in this PR. The value is now explicit in the config so any future
default change won't affect existing simulation runs.

---

## 3. `_compatible` missing haskey guard (should fix)

**File:** `src/weighting/phase_space.jl`

Added `haskey(m.data, prefix) || return false` at the top of
`_compatible(m::Frame, ps::PhaseSpace; ...)`. Without this, an M frame missing the
`"injection"` key would walk the parent chain and throw `KeyError` instead of quietly
returning false.

---

## 4. `build_phase_space` prefix as keyword argument (should fix)

**File:** `src/weighting/phase_space.jl`

Changed `prefix::String="injection"` from a positional argument to a keyword argument,
consistent with `oneweight`, `oneweights`, and `oneweights!`. All internal call sites
updated (`build_phase_space(m, prefix)` → `build_phase_space(m; prefix)`).

---

## 5. Tests for `_validate_geometry_hash!` (should fix)

**File:** `test/test_weighting.jl`

Added three tests in a new `"geometry_hash validation"` testset:

- `test_validate_geometry_hash_mismatch` — G frame and M frame with mismatched hashes;
  asserts `_validate_geometry_hash!` throws `ErrorException`.
- `test_validate_geometry_hash_match` — same hash on both; asserts silent return.
- `test_validate_geometry_hash_no_g_parent` — M frame with no G parent; asserts the
  validator skips it rather than throwing.

---

## 6. Mixed-strategy TamboFrames test (nice to have)

**File:** `test/test_weighting.jl`

Added `test_mixed_strategy_campaigns` to the `"Multi-campaign oneweight"` testset. The
test builds a `TamboFrames` with both a neutrino campaign (pdg=16) and a CR campaign
(pdg=2212) sharing the same geometry hash. It verifies that each Q frame receives a
non-zero one-weight equal to the single-campaign result, and that the incompatible
campaign contributes nothing.

---

## 7. Zero nevent warning + test (nice to have)

**File:** `src/weighting/phase_space.jl`, `test/test_weighting.jl`

`_oneweight_from_ps` now emits a `@warn` when a compatible `PhaseSpace` has `nevent=0`,
since this is almost certainly a config mistake rather than an intentional zero. The
warning includes the PS type, pdg, and event_id.

Added `test_zero_nevent_warns_and_returns_zero` to confirm the warning fires and the
returned one-weight is zero.

---

## Test count

| Before | After |
|--------|-------|
| 53     | 59    |
