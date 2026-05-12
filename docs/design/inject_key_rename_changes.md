# inject-key-rename branch — Changes Summary

## 1. Rename `close_state` → `taurunner_output_state` (neutrino injection)

**Files:** `src/injection/inject.jl`, `examples/interactive/3_injection_walkthrough.jl`

`"$(prefix)_close_state"` was renamed to `"$(prefix)_taurunner_output_state"` on
neutrino Q frames. The new name is more descriptive: this key holds the particle
(neutrino or tau) at the point where TauRunner's stopping condition fired somewhere
along the trajectory through the Earth — it is not necessarily near the detector.

## 2. Proton injection: drop surface-sampled state, rename altitude state

**Files:** `src/injection/inject.jl`, `test/test_proton_injection.jl`,
`examples/interactive/3_injection_walkthrough.jl`

Previously, proton Q frames carried two keys:
- `"$(prefix)_initial_state"` — proton at the sampled point on the detector surface
- `"$(prefix)_final_state"` — proton backtraced to altitude, ready for CORSIKA

The surface-sampled state was not used by any physics code (only by the walkthrough
example), so it was dropped. The altitude state was renamed to
`"$(prefix)_initial_state"`, making its meaning consistent with the neutrino case:
the particle at the physical starting point of the shower.

Proton Q frames now carry only:
- `"$(prefix)_initial_state"` — proton at altitude, the CORSIKA injection input
- `phase_space_point`

## 3. Neutrino `initial_state.position` moved to Earth entry

**Files:** `src/injection/inject.jl`, `src/julia_interfaces/taurunner.jl`

Previously, `"$(prefix)_initial_state"` had its position set to `p`, the sampled
point on the detector surface. The energy was a source-spectrum draw used for
weighting; the position was a bookkeeping artefact with no physical meaning.

`initial_state.position` is now set to `last(intersections).point` — the outermost
intersection of the backward ray with the terrain mesh (slab case) or the PREM outer
sphere (deep-Earth case). This is where the neutrino enters the planet, which is where
TauRunner actually starts its propagation.

The energy and direction of `initial_state` are unchanged, so weights are unaffected.

### Structural change in `taurunner_interface` (spherical case)

Passing `earth_entry` as `particle.position` instead of the detector point required
updating the output position formula in the spherical-Earth branch from:

```julia
# Old: step backward from detector by remaining distance
distance_natural = (TR.x_to_d(track, 1.0) - TR.x_to_d(track, tr_particle.position)) * earth_length
position = distance_natural / TR.units.meter * u"m" * reverse(particle.direction) + particle.position
```

to:

```julia
# New: step forward from Earth entry by traveled distance
distance_natural = TR.x_to_d(track, tr_particle.position) * earth_length
position = distance_natural / TR.units.meter * u"m" * particle.direction + particle.position
```

These are algebraically identical (`remaining * (-d) + detector = traveled * d + earth_entry`
since `detector = earth_entry + chord_length * d`). The slab case was already unaffected
as it never used `particle.position` in its output calculation.

## 4. Rename P frames → R frames (Reconstructed)

**Files:** `src/frames/frame.jl`, `src/frames/tambo_frames.jl`,
`test/test_frames.jl`, `examples/interactive/1_frame_usage.jl`, `README.md`

The per-particle stream character `'P'` was renamed to `'R'` (Reconstructed).
Changes:

- `STREAM_HIERARCHY`: `('G','C','D','M','Q','P')` → `('G','C','D','M','Q','R')`
- `_STREAM_PROPERTY`: `:p_frames => 'P'` → `:r_frames => 'R'`
- `_COLLAPSE_STREAMS`: `('Q','P')` → `('Q','R')`
- All docstrings, examples, and README hierarchy descriptions updated
- Test helper renamed `p` → `r`; `tf.p_frames` → `tf.r_frames` throughout

R frames are not yet populated by the simulation pipeline — this is a
forward-looking naming fix only.

## 5. Rename `pinecone` → `seed` (config key)

**Files:** `src/injection/inject.jl`, `src/julia_interfaces/taurunner.jl`,
`resources/configuration_examples/tau_neutrino_cc.toml`,
`resources/configuration_examples/cosmic_ray_proton.toml`,
`test/test_proton_injection.jl`, `test/test_simulation_api.jl`,
`examples/interactive/3_injection_walkthrough.jl`,
`examples/interactive/4_propagation_walkthrough.jl`,
`examples/templates/3_inject.jl`, `examples/templates/4_propagate.jl`,
`examples/templates/5_run_corsika.jl`, `examples/_internal/make_example_output.jl`

The internal config key `"pinecone"` was renamed to `"seed"` throughout all
source, test, example, and configuration files. The new name is self-documenting
and matches the key used in the CORSIKA section.

## 6. Remove `earth_path` from G frame

**Files:** `src/geometry/earth.jl`, `src/frames/io.jl`,
`test/test_frames.jl`, `test/test_simulation_api.jl`,
`examples/interactive/1_frame_usage.jl`,
`resources/geometry/colca_valley_3000.jld2`,
`examples/resources/example_output.jld2`

`build_gcd_bundle` previously stored the source HDF5/PLY path as
`"earth_path"` in the G frame dict. Since G frames already carry all geometry
data (`prem`, `topography`, `bvh`, `cs`, `geometry_hash`) and are fully
self-contained after save, the path is redundant.

Changes:
- Removed `"earth_path" => earth_path` from the G frame dict in
  `build_gcd_bundle`.
- Removed the lazy-load trigger in `_reconstruct_frames` that called
  `load_earth!` when a G frame had `earth_path` but no `bvh`. New G frames
  always carry `bvh`, so this branch was dead for all current files. The
  `load_earth!` function is retained as an internal utility for backward
  compatibility with old fixtures.
- Updated the `test_g_frame_round_trip` assertion to check `geometry_hash`
  instead of `earth_path`.
- Updated `test_frame_with_parents` to use `geometry_hash` as the inherited
  key under test.
- Updated `1_frame_usage.jl` to show `geometry_hash` as a representative
  inherited G-frame key.
- Regenerated `colca_valley_3000.jld2` and `example_output.jld2` to reflect
  the new schema.

## Tests added

- `test_initial_state_at_earth_entry` (`test_simulation_api.jl`): for each survived
  neutrino Q frame, verifies `initial_state.position` is not NaN, is distinct from
  `taurunner_output_state.position`, and that the displacement between them is
  collinear with the neutrino direction.

- `test_spherical_position_formula_equivalence` (`test_julia_interfaces.jl`): pure
  algebraic test sweeping `fraction_traveled` ∈ {0, 0.1, 0.5, 0.73, 0.99, 1.0} to
  confirm the old and new spherical-case position formulas produce identical results.
