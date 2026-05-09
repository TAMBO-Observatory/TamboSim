# Weighting refactor — implementation notes

**Branch:** `weights-refactor-impl`
**Status:** complete on `weights-refactor-impl`, pending review for merge into `v1-staging`.

This document records the decisions made during implementation and how they relate to the original design proposal (`weighting.md`).

---

## 1. Decisions that follow the proposal exactly

- **Abstract type hierarchy.** `PhaseSpace` and `PhaseSpacePoint` are declared as proposed. All five concrete types (`NeutrinoInjectionPS`, `ForcedNeutrinoInteractionPoint`, `UpstreamNeutrinoInteractionPoint`, `CosmicRayInjectionPS`, `SurfaceCRPoint`) are implemented.

- **Multiple dispatch for PS/Point compatibility.** Incompatible combinations (e.g. `CosmicRayInjectionPS` called with a `ForcedNeutrinoInteractionPoint`) return zero via a fallback method rather than crashing. A `@warn` is emitted from the fallback because hitting it in practice indicates a wiring bug.

- **`oneweight` public API.** `oneweight(tf, q)` and `oneweights(tf)` are implemented as specified, returning `GeV·m²·sr`. `oneweights!` was added as a convenience that writes the result directly onto each Q frame under a configurable key (default `"oneweight"`).

- **`build_phase_space` factory.** Reads the M frame's injection config dict and constructs the appropriate PS subtype. Since `742c7ab`, neutrino vs cosmic-ray dispatch is keyed on an explicit `"strategy"` field rather than the presence of `"xs_location"` (strict error on missing/unknown). Accepts an optional `prefix` argument (default `"injection"`) matching the injection loop's convention.

- **Null/failed events.** `oneweight` returns `0.0u"GeV*m^2*sr"` with a warning when `q["phase_space_point"]` is absent, keeping the output vector aligned with `tf`.

- **Serialization.** `PhaseSpacePoint` structs are stored directly as JLD2 typed structs. `PhaseSpace` functors are regenerated on the fly via `build_phase_space` from the M frame's config dict. PS structs are cheap to reconstruct, and avoiding serializing them insulates old output files from struct renames.

---

## 2. Decisions that deviate from or extend the proposal

### 2.1 Field split: `area`, `cd`, `rho`, `sigma`, `dsigma` are per-event

The proposal showed `area` in `NeutrinoInjectionPS` (campaign-level). After reading the injection loop, we confirmed that `area = sum(visible_areas)` is recomputed for each sampled direction and therefore varies event-by-event. Similarly, `cd`, `rho`, `sigma`, and `dsigma` are computed per forced-CC interaction. All five fields were moved to the Point structs.

### 2.2 Geometry compatibility: M-snapshot of `geometry_hash`, not per-Point

The proposal did not specify how to check that a PS and a PhaseSpacePoint come from compatible detector geometries. We considered (E1) carrying `geometry_hash::UInt` and `pdg::Int` on every Point, vs. (E2) snapshotting both onto the M frame's injection config and filtering PS by M before evaluating any single Q. We chose **E2**.

Reasoning:
- `save_frames` defaults to writing `('M', 'Q')` together, so a Q frame is always loaded alongside its M frame. The "Point self-describing" defense for E1 was answering a problem that doesn't occur in practice.
- E2 lets us filter incompatible campaigns once at the M↔PS level, leaving the per-event functor concerned only with phase-space bounds. Two responsibilities, two `_compatible` methods.
- Removes denormalization: campaign-level facts (geometry, species) live in exactly one place per Q-side (M's `"injection"` dict).
- Shrinks serialized Q frames meaningfully — the per-event redundancy of campaign-level facts under E1 dominates the Point payload at realistic event counts.

Implementation:
- A `_geometry_hash` helper computes `hash(coords)` over a flat `Vector{Float64}` of raw vertex coordinates (PREM radii + topography vertex positions), avoiding Julia's struct-level `hash` which may use `objectid` for non-isbits types.
- The hash is stored as `g_frame["geometry_hash"]` at construction time in `build_gcd_bundle` and recomputed (with a mismatch warning) in `load_earth!`. A defensive `_ensure_geometry_hash!(g_frame)` fallback lazily derives it from prem+topography for legacy fixtures that predate the field, and is called from both `_ensure_earth_loaded!` and `_reconstruct_frames`.
- At injection time, `_setup_injection` snapshots `g_frame["geometry_hash"]` into the M frame's config dict alongside the user's injection knobs.
- `build_phase_space` reads `geometry_hash` and `pdg` from `m[prefix]` (the snapshotted dict), and the resulting PS struct carries both as plain fields.

### 2.3 Two-method `_compatible`: campaign filter vs. per-event bounds

`_compatible` is split:
- `_compatible(m::Frame, ps::PhaseSpace; prefix="injection")` — campaign-level. Compares `m[prefix]["geometry_hash"]` and `m[prefix]["pdg"]` against the PS struct fields. `_oneweight_from_ps` filters the PS list with this before touching the per-event functor; campaigns from a different geometry or species drop out cleanly.
- `_compatible(ps::PhaseSpace, pt::PhaseSpacePoint)` — per-event. Checks energy, theta, and phi against the PS's sampled range. φ uses `mod2pi(pt.phi - ps.phimin) < (ps.phimax - ps.phimin)` so that an event sampled in `[3π/2, 5π/2]` still admits an event whose `cart_to_sph` reading sits at `-π/2`. Energy and theta use half-open intervals (`emin <= E < emax`) so adjacent campaigns sharing a boundary value are disjoint, not double-counted.

### 2.4 Load-time validator

`load_frames` calls `_validate_geometry_hash!(tf; prefixes=("injection",))` after reconstructing parents. For each M with both a parent G and a snapshotted hash, it asserts the snapshot matches `g["geometry_hash"]`; mismatches `error` with a clear message about loading the wrong G alongside an M+Q file. Skips silently when either side lacks a hash (legacy fixtures).

This complements the campaign-level `_compatible` filter: the filter prevents wrong weights at compute time; the validator prevents the user from ever silently pairing a saved campaign with the wrong geometry.

### 2.5 Vectorized API precomputes functors once

`oneweights` and `oneweights!` build `[build_phase_space(m) for m in tf.m_frames]` once before iterating over Q frames. `oneweight(tf, q)` rebuilds them per call — appropriate for single-event interactive use. The shared inner logic lives in `_oneweight_from_ps(q, phase_spaces; prefix)`. All three public entry points accept a `prefix` kwarg that propagates through the campaign-level `_compatible` filter.

### 2.6 Units: functors return `GeV^-1 * m^-2 * sr^-1`

Each functor returns the per-event contribution to the inverse one-weight in `GeV^-1 * m^-2 * sr^-1` (via `uconvert`). `oneweight` inverts the weighted sum and converts to `GeV * m^2 * sr`. PS and Point fields carry their physical units directly via `Quantity{Float64, dim, typeof(u"…")}`, removing the unit-reattachment dance that earlier drafts had inside the functor body.

### 2.7 Inlined forced-CC math; deletion of `WeightParameters`

The forced-CC functor used to call `p_mc(wp)` and `p_phys(wp)` from `compute_weights.jl`. Those helpers (and `WeightParameters`, `null_params`, `p_mc_surface`, `InjectionEvent`) are now deleted; the math is inlined in the functor body, mirroring the algebra of the deleted helpers (separate `mc` and `phys` blocks, no algebraic simplification). This removes the parallel weight pipeline and makes `phase_space.jl` self-contained.

---

## 3. What remains

- **Examples migration.** `examples/interactive/{1,2,3,4}_*.jl` reference `weight_params` in comments and one real read at `2_analyze_output.jl:87`. To be replaced with `oneweights(tf)` in a follow-up commit.
- **Geometry fixture regen.** Old G-only JLD2 fixtures (`resources/geometry/colca_valley_3000.jld2` etc.) lack a stored `geometry_hash`. The `_ensure_geometry_hash!` fallback covers them at load time, but a one-shot regeneration sweep would let us drop the fallback later.
