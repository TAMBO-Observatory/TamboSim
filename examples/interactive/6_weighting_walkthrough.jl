# 6_weighting_walkthrough.jl
#
# Explain how TamboSim turns a simulated event into a flux-independent
# one-weight: the PhaseSpace and PhaseSpacePoint objects each Q frame
# pairs with, the per-event functor that produces a density, and the
# multi-campaign aggregator that inverts the sum.
#
# Designed to be pasted into the REPL section by section.
#
# This walkthrough loads the canonical example output rather than running
# inject! from scratch — the goal is to dissect what the weighting layer
# does, not to re-derive injection. For inject! mechanics, see
# 3_injection_walkthrough.jl.
#
# Topics covered:
#   1. Loading the fixture and locating the weighting inputs
#   2. PhaseSpace — campaign-level phase-space description (one per M frame)
#   3. PhaseSpacePoint — per-event coordinates (one per Q frame)
#   4. _compatible — campaign-level filter and per-event sampler bounds
#   5. The per-event density functor: ps(pt)
#   6. From density to one-weight: _oneweight_from_ps
#   7. The public API: oneweights(tf)
#   8. Multi-campaign aggregation

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using TamboSim
using Unitful: @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
example_file  = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

# =============================================================================
# 1. Loading the fixture
# =============================================================================
# load_frames stitches geometry + simulation output together and runs a
# load-time validator that errors if M's snapshotted geometry_hash doesn't
# match the loaded G's hash — i.e. if you accidentally paired the wrong
# G with this M+Q file, you'd see an error here rather than silently wrong
# weights downstream.

frames = load_frames([geometry_file, example_file])

m = frames.m_frames[1]              # the (single) injection campaign
q1 = first(frames.q_frames)         # one event to dissect

# Each Q frame has a `phase_space_point` key (stamped by inject! during the
# injection loop) and inherits the campaign config from its parent M:
@show haskey(q1.data, "phase_space_point");
@show haskey(q1, "injection");      # walks up to M's snapshot

# =============================================================================
# 2. PhaseSpace — campaign-level phase-space description
# =============================================================================
# A `PhaseSpace` object describes the *campaign* that produced a batch of
# events: the species injected, the energy range and spectral index, the
# angular box, the geometry it was injected against, and how many events
# were thrown. There is exactly one PhaseSpace per M frame.
#
# `build_phase_space(m)` constructs it from M's `injection` config snapshot.
# The factory dispatches on `cfg["strategy"]` to pick the subtype:
#   "NeutrinoInjection"   — propagation through Earth, possibly forced CC
#   "CosmicRayInjection"  — surface sampling, no Earth transit

ps = TamboSim.build_phase_space(m)
@show typeof(ps);

# Fields worth pointing at:
@show ps.geometry_hash;             # snapshotted from G at injection time
@show ps.pdg;                       # 16 (nu_tau)
@show ps.emin, ps.emax;             # GeV bounds, with units attached
@show ps.gamma;                     # spectral index for the power-law term
@show ps.nevent;                    # number of events generated in this campaign

# =============================================================================
# 3. PhaseSpacePoint — per-event coordinates
# =============================================================================
# A `PhaseSpacePoint` holds the per-event physics that the weighting
# formula needs. There are three concrete subtypes thus far, one per kind of 
# event the injection loop can produce:
#
#   ForcedNeutrinoInteractionPoint   — neutrino reached the rock and was
#                                      forced to interact. Carries the
#                                      column depth, density, and sigma /
#                                      dsigma at the forced vertex.
#
#   UpstreamNeutrinoInteractionPoint — neutrino was converted to a charged
#                                      lepton during Earth transit (no
#                                      forced interaction needed).
#
#   SurfaceCRPoint                   — cosmic-ray primary sampled at the
#                                      detector surface. Same shape as the
#                                      upstream-converted case.
#
# All three carry (E, θ, φ, area). The forced-CC variant additionally carries
# the column-depth + cross-section quantities that the importance-sampling
# correction needs.

pt = q1["phase_space_point"]
@show typeof(pt);

@show pt.E;                         # the source-side energy actually drawn for this event
@show pt.theta, pt.phi;             # zenith / azimuth, in radians
@show pt.area;                      # visible detector area along this direction

# =============================================================================
# 4. _compatible — two-method check
# =============================================================================
# Before evaluating the per-event density, the weighting layer asks two
# separate questions:
#
#   _compatible(m, ps)     — does this PhaseSpace describe the same
#                            campaign (geometry + species) as M? This is
#                            the campaign-level filter; mismatches drop
#                            the PS from the sum entirely.
#   _compatible(ps, pt)    — does this Point fall inside the PhaseSpace's
#                            sampler bounds (E, θ, φ)? Out-of-bounds
#                            events return zero density without warning.
#
# Both are internal helpers (not exported) but inspectable.

@show TamboSim._compatible(m, ps);          # true — m and ps came from the same campaign
@show TamboSim._compatible(ps, pt);         # true — pt falls inside ps's bounds

# Half-open intervals on the upper bound: an event at exactly E == ps.emax
# belongs to the *next* campaign, not this one. Same convention for theta.
# The phi check uses mod-2π so a sampler that wraps past 2π (e.g. [3π/2,
# 5π/2]) still admits an event whose `cart_to_sph` reading sits at -π/2.

# =============================================================================
# 5. The per-event density functor: ps(pt)
# =============================================================================
# `ps(pt)` returns the per-event contribution to the inverse one-weight,
# in units of GeV⁻¹ · m⁻² · sr⁻¹. The formula depends on the (PS, Point)
# pair — multiple-dispatch picks the right method:
#
#   NeutrinoInjectionPS(ForcedNeutrinoInteractionPoint)
#       generation density × (rho/cd) × (dsigma/sigma)         (MC factor)
#       divided by
#       (cd / m_iso) × (rho/cd) × dsigma                       (physical factor)
#
#   NeutrinoInjectionPS(UpstreamNeutrinoInteractionPoint)
#       just the surface generation density (no forced-interaction terms)
#
#   CosmicRayInjectionPS(SurfaceCRPoint)
#       same surface generation density formula
#
# The forced-CC math collapses the importance-sampling boost that
# inject_neutrino_event applied to focus events on the detector. The surface cases
# don't force an interaction, so there's nothing to undo.

dens = ps(pt)
@show dens;                                  # GeV⁻¹ · m⁻² · sr⁻¹

# =============================================================================
# 6. From density to one-weight: _oneweight_from_ps
# =============================================================================
# For a single Q against a list of PhaseSpaces, the one-weight is the
# inverse of the sum of per-PS densities, weighted by each campaign's
# `nevent`:
#
#       oneweight(q) = 1 / Σ_ps  ps(pt) * ps.nevent
#
# The sum runs only over PhaseSpaces that pass the M-level filter
# (_compatible(m, ps)) — incompatible campaigns don't contribute.
#
# Internally:

ow1 = TamboSim._oneweight_from_ps(q1, [ps])
@show ow1;                                   # GeV · m² · sr — units flip on inversion

# Spot-check the formula by hand:
@show inv(ps(pt) * ps.nevent);               # matches ow1

# =============================================================================
# 7. The public API: oneweights(tf)
# =============================================================================
# `oneweights(tf)` builds one PhaseSpace per M frame, then runs
# `_oneweight_from_ps` for every Q frame. `oneweight(tf, q)` and
# `oneweights!(tf)` are the per-event and in-place variants.

@doc oneweights

ows = oneweights(frames)
@show length(ows);                           # one per Q frame
@show first(ows);                            # matches ow1 above

# `oneweights!` writes the result back onto each Q frame under "oneweight":
oneweights!(frames)
@show frames.q_frames[1]["oneweight"];

# Multiplying a OneWeight by a flux dN/(dE·dA·dt·dΩ) (units 1/(GeV·m²·s·sr))
# and an exposure time (s) gives the expected event count under that flux.

# See 2_analyze_output.jl for an example! :) 

# =============================================================================
# 8. Multi-campaign aggregation
# =============================================================================
# The fixture only has one campaign, but `oneweights` is built to combine
# arbitrary numbers. The classic use case is staged generation: a low-energy
# campaign with one nevent and a high-energy campaign with another, sharing
# a boundary energy. Per-event density is summed across compatible campaigns:
#
#       oneweight(q) = 1 / (n1 * ps1(pt) + n2 * ps2(pt) + ...)
#
# The per-event _compatible check (energy / θ / φ bounds) zeros out
# campaigns whose sampler doesn't cover this event, and the M-level filter
# zeros out campaigns from a different geometry or species. So you can
# safely call `oneweights(tf)` on a TamboFrames containing multiple
# unrelated injection campaigns — each Q only collects contributions from
# the campaigns whose PhaseSpace actually covers it.
#
# Half-open intervals on energy / θ mean adjacent campaigns sharing a
# boundary value are disjoint, not double-counted.
#
# Aggregation across non-overlapping *geometries* is handled the same way:
# each Q's M frame snapshots its own `geometry_hash`, and the M-level
# filter only admits PhaseSpaces whose hash matches — so loading several
# campaigns from different sites into one TamboFrames just works, with
# each Q drawing only from its own site's PhaseSpace.
