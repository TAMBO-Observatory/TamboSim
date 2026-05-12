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

## Tests added

- `test_initial_state_at_earth_entry` (`test_simulation_api.jl`): for each survived
  neutrino Q frame, verifies `initial_state.position` is not NaN, is distinct from
  `taurunner_output_state.position`, and that the displacement between them is
  collinear with the neutrino direction.

- `test_spherical_position_formula_equivalence` (`test_julia_interfaces.jl`): pure
  algebraic test sweeping `fraction_traveled` ∈ {0, 0.1, 0.5, 0.73, 0.99, 1.0} to
  confirm the old and new spherical-case position formulas produce identical results.
