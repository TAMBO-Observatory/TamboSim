# PR #79 Review — New Weights Implementation

**Branch:** `weights-refactor-impl`
**Author:** kcarloni
**Reviewer:** jlazar17

---

## Must Fix

### 1. `_geometry_hash` uses Julia's non-stable `hash()` — FIXED
`hash()` on `Vector{Float64}` is not stable across Julia minor versions (changed in 1.6→1.7 and again in 1.9). A geometry bundle written with one Julia version will have a different hash under another, causing `_validate_geometry_hash!` to throw on every `load_frames` call after a Julia upgrade.

**Fix applied:** replaced `hash(coords)` with SHA256 over the raw IEEE 754 bytes of the coordinate vector, returning the first 8 bytes as `UInt64`. `SHA` is a Julia stdlib (no new dependency).

**Side effect:** any committed geometry JLD2 that already has a stored `geometry_hash` (written with the old `hash()`) will have a different value than what the new function computes. `_ensure_geometry_hash!` and the mismatch warning in `load_earth!` will fire for those files. A one-shot regeneration of `resources/geometry/colca_valley_3000.jld2` (and any other committed bundles) is needed after merging.

---

### 2. Default proton injection altitude silently changed: 50 km → 112 km

`inject_proton_event` and `inject_protons!` changed the default altitude from 50 km to 112 km. `cosmic_ray_proton.toml` does not set `altitude` explicitly, so any simulation run with that config will silently inject protons from a different starting point after upgrade. This is a physics-significant change that needs to be:

- Called out in user-facing release notes / CHANGELOG
- Pinned explicitly in `cosmic_ray_proton.toml` so the default is never implicitly relied upon

---

### 3. `particle_passes_through_rock` key removed without documentation

This per-event Bool on proton Q frames was the natural filter for shielded-primary cuts in CORSIKA analyses. Its removal is not mentioned anywhere in the PR description, docs, or comments. Either document that it's gone and why, or provide an equivalent.

---

## Should Fix

### 4. `_compatible(m, ps)` missing guard — can throw instead of returning false

If an M frame lacks the `"injection"` key, `m[prefix]` walks the parent chain and then throws `KeyError` rather than returning `false`. Add at the top of `_compatible(m::Frame, ps::PhaseSpace; ...)`:

```julia
haskey(m.data, prefix) || return false
```

### 5. `build_phase_space` prefix should be a keyword argument

`build_phase_space(m::Frame, prefix::String="injection")` takes `prefix` as a positional argument, while `oneweight`, `oneweights`, and `oneweights!` all take `prefix` as a keyword. Callers who override the prefix need to use different call syntax for `build_phase_space` vs. the public API. Make it `prefix::String="injection"` as a keyword for consistency.

### 6. Per-event fallback `@warn` needs rate limiting

The fallback `(ps::PhaseSpace)(pt::PhaseSpacePoint)` method emits `@warn` once per event. In a large mixed-strategy `TamboFrames` this produces overwhelming log output. The campaign-level `_compatible` filter in `_oneweight_from_ps` should prevent the fallback from being reached in normal usage — if it does fire, it indicates a wiring bug and should warn once per PS/PT type combination, not once per event. Consider using a `Ref{Bool}` flag or a `Set` of seen type pairs.

### 7. `_validate_geometry_hash!` has no test

The most important correctness guard in the PR — the load-time error when loading a wrong G frame alongside saved M+Q frames — is not covered by any test. Add a test that:
1. Builds a `TamboFrames` with one geometry, saves it
2. Loads it with a different G frame (different hash)
3. Asserts that `_validate_geometry_hash!` throws with a clear message

---

## Nice to Have

### 8. Document the `ρ/cd` and `dσ` near-cancellations in the forced-CC functor

The forced-CC functor computes `mc/phys` where `ρ/cd` and `dσ` appear in both numerator and denominator and nearly cancel. This is intentional (mirroring the algebra of the deleted helpers), but a reader will be tempted to "simplify" it incorrectly. Add a comment:

```julia
# ρ/cd and dσ cancel in mc/phys; kept expanded to mirror the deleted p_mc/p_phys helpers.
```

### 9. Add mixed-strategy `TamboFrames` test

A `TamboFrames` with both neutrino and CR campaigns should correctly assign zero weight to events from the incompatible campaign. This is documented as supported behavior but has no test.

### 10. Zero `n_event` in PS should warn

When `ps.nevent == 0`, `_oneweight_from_ps` silently returns `_zero_ow`. This case (a campaign with zero events recorded) is almost certainly a user error — distinct from the intentional failed-event zero. Add a `@warn` and a dedicated test.

### 11. Migration guide for deleted API surface

The following are hard breaks with no migration path documented:

| Deleted | Replacement |
|---|---|
| `q["weight_params"]` key | `q["phase_space_point"]` |
| `WeightParameters` struct | `PhaseSpacePoint` subtypes |
| `p_mc(wp)`, `p_phys(wp)`, `p_mc_surface(wp)` | `oneweight(q)` |
| `InjectionEvent` | `ForcedNeutrinoInteractionPoint` / `UpstreamNeutrinoInteractionPoint` |
| `inject_protons!` (unexported) | `inject!(frames, config)` |
| `tau_neutrino_cc_fine_ecut.toml` | `tau_neutrino_cc.toml` |

Old JLD2 files with `weight_params` will silently return zero weights (with a per-event `@warn`) rather than throwing — easy to miss. A `MIGRATION.md` or CHANGELOG section covering these would prevent silent wrong analyses.

---

## Summary Table

| Priority | Item | Status |
|---|---|---|
| Must fix | Unstable `hash()` in `_geometry_hash` | **Fixed in this session** |
| Must fix | Undocumented 50→112 km altitude default change | Open |
| Must fix | `particle_passes_through_rock` removal undocumented | Open |
| Should fix | `_compatible` missing `haskey` guard | Open |
| Should fix | `build_phase_space` prefix should be kwarg | Open |
| Should fix | Rate-limit per-event fallback `@warn` | Open |
| Should fix | Add test for `_validate_geometry_hash!` error path | Open |
| Nice to have | Comment on forced-CC functor cancellations | Open |
| Nice to have | Mixed-strategy `TamboFrames` test | Open |
| Nice to have | Zero `n_event` warning + test | Open |
| Nice to have | Migration guide for deleted API surface | Open |
