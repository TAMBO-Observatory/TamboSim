# Weighting refactor — design notes

**Status:** draft, pre-implementation. Brainstorm between Kiara and Claude on 2026-05-01. Open for Jeff's review.
**Branch:** `weights-refactor` (off `v1-staging`).
**Goal:** a single, coherent in-package weighting interface so consumers don't reimplement the one-weight formula and so it remains correct under reweighting, multi-injection-config, and multi-site workflows.

---

## 1. Motivation

The current one-weight handling is scattered:

- Per-Q-frame inputs live in `WeightParameters` on the `"weight_params"` key.
- `p_phys`, `p_mc`, `p_mc_surface` are top-level functions on `WeightParameters` (`src/weighting/compute_weights.jl`).
- The `oneweight = (p_phys / p_mc) / n_gen` formula is **reimplemented inline** in:
  - `examples/interactive/2_analyze_output.jl:94`
  - `examples/interactive/3_injection_walkthrough.jl:227, 328`
  - (also in `TamboMakie.jl/src/plotting/effA.jl::get_p`, but TamboMakie is being completely overhauled for TamboSim v1 in a separate effort and is **out of scope** for this refactor)
- Forced vs. surface vs. upstream-converted events are discriminated by **NaN sentinels** on `WeightParameters` fields (`generated_xs`, `generated_cd`). Easy to misread; downstream code has to know the convention.
- No support for combining two simulation sets with **overlapping phase spaces** — `get_mctable_for_effA_no_overlap` openly warns it's incorrect under overlap.
- No support for combining sets that target **different geometry sites** (different G frames in one `TamboFrames`).

We want a single function `oneweight(tf, q)` that handles all the cases (forced ν, surface proton, upstream-converted lepton, multi-config overlap, multi-site) correctly and that all downstream code can call.

## 2. Current state — quick map

### 2.1 `WeightParameters` (today)

`src/weighting/weight_parameters.jl:22-38`. Single concrete struct holding:

- Phase-space parameters: `area`, `emin`, `emax`, `gamma`, `thetamin/max`, `phimin/max`.
- Per-event sampled quantities: `generated_initial_e` (always finite for non-null events), `generated_final_e`, `generated_cd`, `generated_density`, `generated_xs`, `generated_diff_xs`.

The NaN pattern of those sampled fields is the only signal of which physics path produced the event:

| Path                                | `generated_final_e` | `generated_cd` / `density` | `generated_xs` / `diff_xs` |
|-------------------------------------|---------------------|----------------------------|-----------------------------|
| Forced ν CC interaction             | finite              | finite                     | finite                      |
| TauRunner already converted ν → ℓ   | NaN                 | NaN                        | NaN                         |
| Surface-injected proton             | NaN                 | NaN                        | NaN                         |
| Null / failed injection             | NaN                 | NaN                        | NaN                         |

Note: TauRunner-converted and surface-injected currently look identical at the field level. They are distinguished by which *other* frame keys are present (`particle_passes_through_rock` for protons; `injection_close_state == injection_final_state` for upstream-converted) and by the parent M frame's config. This is fragile.

### 2.2 `p_mc`, `p_mc_surface`, `p_phys` (today)

`src/weighting/compute_weights.jl:42-188`.

- `p_mc(wp)` → `GeV⁻¹·m⁻³·sr⁻¹`. Power-law-E × solid-angle × area × (when `cd` finite) `(density/cd)·(diff_xs/xs)`. Falls back to dividing by `1 cm` as a dimensional placeholder when `cd` is NaN — currently never the right answer for surface-injected events; callers explicitly use `p_mc_surface` instead.
- `p_mc_surface(wp)` → `GeV⁻¹·m⁻²·sr⁻¹`. Same minus interaction terms.
- `p_phys(wp)` → `m⁻¹`. `cd / density · diff_xs`-style; returns `0` if `cd` is NaN.

### 2.3 The inline one-weight formulas (today)

```julia
# Forced ν:
oneweight = (p_phys(wp) / p_mc(wp)) / n_gen      # units: GeV · m² · sr

# Surface proton or upstream-converted ν → ℓ:
oneweight = 1 / (p_mc_surface(wp) * n_gen)       # units: GeV · m² · sr
```

`n_gen` is read from the parent M frame's injection config (`m_frame[prefix]["nevent"]`).

### 2.4 `TamboFrames` capacity for multi-set / multi-site

`src/frames/tambo_frames.jl`. `TamboFrames` is a thin `AbstractVector{Frame}` wrapper over a depth-first linearization of the frame tree. Each `Frame` has a `parents::IdDict{Char,Frame}`; per-frame property accessors (`q.g_frame`, `q.c_frame`, `q.d_frame`, `q.m_frame`) walk *that* frame's parents. Container-level accessors (`tf.g_frames`, `tf.m_frames`, …) flat-scan the whole vector by stream char.

**Implication:** a `TamboFrames` can already legally hold multiple G subtrees and multiple M frames. Each Q frame unambiguously knows its own G/C/D/M via its `parents` map. The linearization is DFS so the tree is recoverable. Nothing in the current weighting code uses this — everything assumes one G and one M.

## 3. Proposed design

The core idea: each M frame owns a typed `PhaseSpace` functor that knows the campaign's generated phase space + physics. Each Q frame owns a typed `PhaseSpacePoint` that records what was actually sampled. Calling `ps(point)` returns this M frame's **per-event contribution to the inverse one-weight**, in units determined by the PS type, or zero if the point lies outside this PS's support.

Multiple dispatch handles overlap automatically: the one-weight is `1 / Σ ps_M(point) · nevent_M` over all *compatible* M frames (those whose PS type defines a method for the event's Point type); same-strategy out-of-support PSes contribute zero. No partition rectangles, no per-event containment checks, no NaN sentinels.

**The type/species rule.** The PS type encodes the *MC weighting math* — the sampler shape and which formula applies. Species (PDG) lives in a field on the PS instance and can be compared per-event inside the functor (`ps.pdg == pt.pdg`). New types appear only when the math will differ or the attributes could differ:

- a genuinely new strategy (e.g. atmospheric μ injection at a different reference surface → new PS type + new Point type), or
- a new physical realization within an existing strategy (e.g. the forced vs upstream branches of a neutrino campaign → distinct Point types because their fields and formulas differ).

A new species under an existing strategy probably does not need a new type. For example, iron CR primaries could reuse `CosmicRayInjectionPS` + `SurfaceCRPoint` with `pdg = 1000260560`. Tau and muon neutrinos could reuse `NeutrinoInjectionPS` + the two existing neutrino Point types with `pdg = 16` or `pdg = 14`. Cross-species exclusion can be handled by a per-functor PDG check.

**Public API surface:** `oneweight(tf, q)`, `oneweights(tf)`, plus the `PhaseSpace` / `PhaseSpacePoint` type hierarchy declared below.

## Phase space and phase space point types

```julia
abstract type PhaseSpace end
abstract type PhaseSpacePoint end

# --- Neutrino injection (propagation through earth + forced CC near detector) ---

# Describes the generated phase space + physics for one neutrino injection campaign.
# Today's TamboSim only ships ν_τ via TauRunner, but the same math applies to
# ν_μ / ν_e / antineutrinos via their respective propagators.
struct NeutrinoInjectionPS <: PhaseSpace
    g_frame::Frame                  # parent G — fixes the close surface
    pdg::Int                        # ν flavor / particle vs antiparticle
    area; emin; emax; gamma         # phase-space sampler params
    thetamin; thetamax; phimin; phimax
    nevent::Int
    # ...references to xs tables / interaction model
end

# A single neutrino campaign produces points of two flavors depending on whether
# the charged lepton was made by the forced CC or by upstream conversion in the
# propagator:
struct ForcedNeutrinoInteractionPoint <: PhaseSpacePoint
    g_frame::Frame
    pdg::Int
    E; θ; φ
    cd; ρ; σ; dσ                    # forced-CC vertex info
end

struct UpstreamNeutrinoInteractionPoint <: PhaseSpacePoint
    g_frame::Frame
    pdg::Int
    E; θ; φ
end

# --- Cosmic-ray injection (surface sampling, then CORSIKA) ---

struct CosmicRayInjectionPS <: PhaseSpace
    g_frame::Frame                  # parent G — fixes the topography surface
    pdg::Int                        # 2212 (proton) today; Iron / heavier nuclei via the same type
    area; emin; emax; gamma
    thetamin; thetamax; phimin; phimax
    nevent::Int
end

struct SurfaceCRPoint <: PhaseSpacePoint
    g_frame::Frame
    pdg::Int
    E; θ; φ
end
```

Each `ps(pt)` returns this M frame's per-event contribution to the inverse one-weight, in units determined by the PS type. The standard one-weight units `(GeV·m²·sr)⁻¹` cover today's strategies.

Notes:
- A single neutrino campaign can produce *both* `ForcedNeutrinoInteractionPoint` and `UpstreamNeutrinoInteractionPoint` events, depending on whether the propagator (today: TauRunner) pre-converted.
- The PS owns its parent G frame, so the geometry-compat check lives inside the functor. Calling `ps(pt)` outside the `oneweight` calculation is still safe.
- The PS type uniquely determines its output units. We don't assume those units are the same across PS types — only that within a single `oneweight` call (which sees only PSes compatible with one Point type) the units are uniform.

## `oneweight` — public API

```julia
"""
    oneweight(tf::TamboFrames, q::Frame) -> Quantity

Per-event one-weight (units determined by the event's PhaseSpacePoint type;
typically `GeV · m² · sr`). Computed as the inverse of the sum, over all
M frames in `tf` whose PS type defines a method for `q`'s Point type, of
`phase_space(m)(point_of_q) * nevent_m`. Same-strategy out-of-support PSes
contribute zero — so phase-space overlap, multi-campaign reweighting, and
multi-site partitioning are all handled by the sum itself.

Mixed-strategy `TamboFrames` (e.g. CR protons + ν_τ campaigns) is supported
in the sense that it doesn't crash — incompatible-strategy M frames are
filtered out by dispatch — but the recommended workflow is to filter
`TamboFrames` by particle type before calling `oneweight`.
"""
oneweight(tf::TamboFrames, q::Frame) -> Quantity

oneweights(tf::TamboFrames) -> Vector{Quantity}
```

## Storage on frames and PS regeneration

On disk, each M frame stores its **config dict** (today's `m["injection"]`), which is a stable, schema-light record of the campaign parameters. PS functors are **regenerated on the fly**:
```julia
phase_space(m::Frame) = build_phase_space(m["injection"], m.g_frame)
```
The idea is this avoids serializing typed PS structs into the JLD2: struct field renames or type-parameter changes between TamboSim versions wouldn't break old output files, and `build_phase_space` becomes the single, code-versioned boundary between on-disk config and in-memory typed functor. There's only one PS per M frame (typically 1–5 per `TamboFrames`), so the construction cost on load is negligible.

`PhaseSpacePoint` structs *are* stored on Q frames as `q["phase_space_point"]`:

- The schema-fragility risk that motivated regenerating PSes is much smaller for Points: there are only a handful of fields per Point type, and the field set rarely changes once a Point type is settled.
- Points are compact (a few `Float64`s) so storage cost is bounded even for `N = 10⁶` events.

The existing per-Q-frame keys (`injection_initial_state`, `injection_close_state`, `injection_final_state`) stay as the human-readable view of the sampled state; `phase_space_point` is the weighting view.

## Performance

`oneweight(tf, q)` is `O(M)` per event, where `M` is the number of M frames. Typical `M ≤ 5` (often 1) makes this fine.

The vectorized `oneweights(tf)` should precompute the phase space functors via `phase_space(m)` before batch-processing the Q frames. Correctness already lives in the dispatch + functors.

## 4. Open questions for Jeff

- **`p_phys` as a public helper.** Is it worth keeping `p_phys(pt::ForcedNeutrinoInteractionPoint)` as the one-arg function it is today? Inputs (`cd`, `density`, `diff_xs`) all live on the Point, so it's well-defined; it could be useful for diagnostics?
- **Failed / null events.** Plan is for them to carry no `phase_space_point` key, with `oneweight` skipping them — does that match what you'd expect, or should they have a typed null sentinel?
- **`hasmethod` filter caching for `oneweights`.** The vectorized form could pre-compute a `(typeof(pt), m)` → bool table once and reuse per event; worth doing eagerly, or only once it shows up in profiles?
- **On-disk format for `PhaseSpacePoint`.** Typed JLD2 struct (fast, fragile under field renames) or a stable Dict / NamedTuple serialization (slower, robust)?