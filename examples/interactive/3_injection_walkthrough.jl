# 3_injection_walkthrough.jl
#
# Run inject! from scratch on the canonical Colca-valley geometry and
# explore what it does to a TamboFrames container. Designed to be pasted
# into the REPL section by section — values display themselves rather
# than being wrapped in println.
#
# This walkthrough produces (modulo the missing PROPOSAL stage) the same
# data that examples/resources/example_output.jld2 carries, by using the
# same seed and event count as _internal/make_example_output.jl.
#
# For frame-container basics, see 1_frame_usage.jl.
#
# Topics covered:
#   1. Inputs to inject!: the geometry G frame + the [injection] TOML table
#   2. Run inject! and survey the result (M frame + Q frames + new keys)
#   3. The samplers and cross section that did the per-event work
#   4. The three injection states and how the sampling inversion sets them
#   5. weight_params and p_mc — the bookkeeping that makes flux estimates work
#   6. Failure mode: when an injected direction doesn't see any rock
#   7. Variant: inject_protons! for cosmic-ray primaries

using Tambo
using TOML

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
config_file   = joinpath(tambo_path, "resources", "configuration_examples", "tau_neutrino_cc.toml")

const SEED   = 1234
const NEVENT = 50

# =============================================================================
# 1. Inputs to inject!
# =============================================================================
# inject! takes a TamboFrames container (must contain a G frame) and a
# parsed [injection] config dict. It mutates the container: pushing one
# new M frame + nevent new Q frames.

@doc inject!

frames = load_frames(geometry_file)
frames                              # tree view: just the G/C/D bundle, no events yet

config = TOML.parsefile(config_file)
relativize!(config)

injection_config = config["injection"]
injection_config["nevent"]   = NEVENT
injection_config["pinecone"] = SEED

# The fields that drive the work:
@show injection_config["pdg"];                            # primary species (16 = nu_tau)
@show injection_config["emin"], injection_config["emax"]; # energy range in GeV
@show injection_config["gamma"];                          # spectral index for the power-law sampler
@show injection_config["thetamin"], injection_config["thetamax"];   # zenith box (degrees)
@show injection_config["phimin"],   injection_config["phimax"];     # azimuth box (degrees)
@show injection_config["xs_location"];                    # path to cross-section table
@show injection_config["pinecone"];                       # RNG seed
@show injection_config["nevent"];                         # number of primaries to throw

# =============================================================================
# 2. Run inject! and survey the result
# =============================================================================
# A single inject! call does two things internally:
#   (a) appends one M frame to the container, snapshotted under the
#       "injection" key, plus `nevent` empty Q frames each tagged with a
#       sequential event_id;
#   (b) loops over those Q frames, sampling and tracing each event, and
#       writes injection_*_state + weight_params onto each frame.
# Sections 3–5 unpack what (b) put where; this section just runs the
# call and shows the resulting shape.

inject!(frames, injection_config)

frames                              # tree view: M frame + 50 Q frames now present
length(frames.q_frames)             # 50

# The M frame carries a snapshot of the config that produced this run:
m_frame = frames.m_frames[end]
sort(collect(keys(m_frame.data)))    # ["injection"]
m_frame["injection"]["nevent"]       # 50 — round-trips from injection_config
m_frame["injection"]["pinecone"]     # 1234

# Each Q frame now has event_id + the per-event physics keys:
q1 = frames.q_frames[1]
q1["event_id"]                      # 1
sort(collect(keys(q1.data)))        # event_id, injection_*_state, weight_params

# =============================================================================
# 3. The samplers and cross section that did the per-event work
# =============================================================================
# The per-event loop in inject! draws from three machines, all configured
# from the [injection] table:
#
#   UnitfulPowerLawSampler     energy ∈ [emin, emax] GeV with dN/dE ∝ E^-gamma
#   UniformAngularSampler      direction uniformly in the zenith/azimuth box
#   CrossSection               neutrino-nucleon σ(E) interpolated from a table
#
# These don't survive on the frames after inject! returns, so to inspect
# them we re-construct a copy here — these are the same constructors inject! uses
# internally.

@doc Tambo.UnitfulPowerLawSampler

@doc Tambo.UniformAngularSampler

# The cross-section table that ships with the canonical config:
xs = Tambo.CrossSection(injection_config["xs_location"])
xs                                  # struct fields show the energy grid + σ values

# =============================================================================
# 4. The three injection states
# =============================================================================
# inject_event uses a sampling-inversion trick to focus events on the
# detector. Rather than throwing primaries on a sphere far from the
# mountain (most would miss), it:
#
#   (1) draws a direction d from the angular box,
#   (2) samples a point p on the detector-region surface (weighted by
#       triangle area + visibility along d),
#   (3) ray-traces the *reverse* direction back through PREM + topography
#       to find the trajectory that would arrive at p, d,
#   (4) hands that trajectory to TauRunner, which propagates a virtual
#       primary along it through Earth and reports what survives at p,
#   (5) forces a CC interaction inside the rock leading up to p, producing
#       a tau at the interaction vertex.
#
# The three saved states correspond to steps (3), (4), (5):
#
#   injection_close_state     the *physical* neutrino arriving at p with
#                             direction d. Position, direction, and energy
#                             are all real: TauRunner sampled the cascade
#                             through Earth (CC interactions, tau decay →
#                             nu_tau regeneration, etc.) and reports what
#                             actually survives at the detector face.
#
#   injection_initial_state   same position p and direction d, but the
#                             energy is a draw from the *source-side*
#                             power-law spectrum — i.e. "what would we be
#                             sampling at p if Earth weren't in the way?"
#                             This is a source-side number attached to a
#                             detector-side location, and it's what makes
#                             the sampling-inversion bookkeeping work.
#                             Used for the weight calculation, not as a
#                             physical state.
#
#   injection_final_state     the forced CC interaction vertex inside
#                             rock — a physically distinct point along
#                             the trajectory leading to p, where close_state
#                             is forced to interact. The outgoing tau
#                             lives here, and its energy/PDG feed PROPOSAL
#                             in the next stage.
#
# Frames whose sampling step (2) found no visible detector triangle, or
# whose back-traced trajectory failed to validate, lack *_final_state —
# see Section 6.

q1["injection_close_state"]         # physical: real neutrino arriving at p
q1["injection_initial_state"]       # bookkeeping: source-side energy attached to p
q1["injection_final_state"]         # interior CC vertex; the input to PROPOSAL

# initial and close share position+direction by construction — the only
# thing that differs between them is the energy. That energy gap is the
# Earth-absorption cascade: at PeV energies the CC mean free path through
# rock is short, so most of the source-side energy is lost in the
# integrated column depth before anything reaches p. TauRunner samples
# that loss; (initial.energy / close.energy) gives the per-event suppression.
q1["injection_initial_state"].energy |> u"PeV"
q1["injection_close_state"].energy |> u"PeV"

# The forced close → final interaction conserves energy approximately
# (Bjorken-y is small at high E), so close and final energies are similar.
q1["injection_final_state"].energy |> u"PeV"

q1["injection_initial_state"].pdg    # 16 (nu_tau)
q1["injection_close_state"].pdg      # still nu_tau if it survived as a neutrino
q1["injection_final_state"].pdg      # 15 (tau) — outgoing charged lepton from the CC

# initial and close share position by construction:
q1["injection_initial_state"].position == q1["injection_close_state"].position    # true

# final lives elsewhere — at the actual interaction vertex inside rock:
q1["injection_final_state"].position

# =============================================================================
# 5. weight_params, p_mc, p_phys, and one-weights
# =============================================================================
# inject_event also filled weight_params on every Q frame (whether or
# not the event survived). These hold the generation phase-space + forced-
# interaction information needed to assign each event a flux-independent
# one-weight.

wp = q1["weight_params"]
wp                                  # struct fields display

# Two probability densities are computed from weight_params:
#
#   p_mc(wp)     the *generation* density — power-law energy term, solid
#                angle, area, AND the forced-interaction factors (column
#                depth and diff_xs/xs) that inject_event applied to focus
#                events on the detector. Units: GeV^-1 · m^-3 · sr^-1.
#
#   p_phys(wp)   the *physical* interaction probability density at the
#                forced vertex (no spectrum, no solid angle — just the
#                natural rate of interaction per unit length). Units: m^-1.
#
# The forced sampling boosted each event's MC weight artificially. The
# importance-sampling correction p_phys / p_mc removes that boost and
# replaces it with the natural physical rate. Dividing by n_gen normalizes
# per generated event:
#
#     oneweight = (p_phys(wp) / p_mc(wp)) / n_gen     # forced neutrino
#
# Units come out to GeV · m² · sr / event — the standard "OneWeight"
# shape. Multiplying by a flux dN/(dE·dA·dt·dΩ) (units 1/(GeV·m²·s·sr))
# and an exposure time (s) gives the expected event count.

@doc Tambo.p_mc

@doc Tambo.p_phys

@show Tambo.p_mc(wp);
@show Tambo.p_phys(wp);

oneweight = (Tambo.p_phys(wp) / Tambo.p_mc(wp)) / NEVENT
@show oneweight;                            

# Note: surface-injected primaries (cosmic-ray protons, atmospheric muons)
# are NOT forced to interact — every primary produces a shower. Those use
# `p_mc_surface(wp)` and skip the p_phys correction.

# =============================================================================
# 6. Failure mode: directions that miss the detector region
# =============================================================================
# Some sampled directions never see the detector region at all (they go
# off into space without hitting rock that contains it). For those frames
# inject_event still wrote weight_params (for accounting), but skipped
# *_final_state. Downstream stages need the final state, so the templates
# cut these frames immediately:
#
#     filter!(frame -> haskey(frame, "injection_final_state"), frames)

n_total  = length(frames.q_frames)
n_failed = count(f -> !haskey(f, "injection_final_state"), frames.q_frames)
n_air    = n_total - n_failed

@show n_total n_failed n_air;

# This walkthrough stops short of the cut so you can still inspect a
# failed frame side-by-side with a successful one:
failed_q = first(filter(f -> !haskey(f, "injection_final_state"), frames.q_frames))
sort(collect(keys(failed_q.data)))  # event_id + weight_params, but no injection_*_state

# Continue with 4_propagation_walkthrough.jl to see what proposal_propagation!
# does with the surviving injection_final_state.

# =============================================================================
# 7. Variant: inject_protons! for cosmic-ray primaries
# =============================================================================
# Cosmic-ray protons are surface-injected: every primary produces a shower
# by construction, so there's no forced CC interaction, no Earth-propagation
# cascade, and no cross-section table. inject_protons! shares the same
# spectrum + angular samplers as inject!, but the per-event work and the
# resulting Q-frame keys are different.

@doc inject_protons!

proton_config_file = joinpath(tambo_path, "resources", "configuration_examples", "cosmic_ray_proton.toml")
proton_config = TOML.parsefile(proton_config_file)
relativize!(proton_config)

proton_injection_config = proton_config["injection"]
proton_injection_config["nevent"]   = NEVENT
proton_injection_config["pinecone"] = SEED

# The proton config has no `pdg` (protons are protons), no `xs_location`
# (no forced interaction), but adds `altitude` — the geodetic altitude at
# which the primary is sampled along its trajectory before entering the
# atmosphere.
@show proton_injection_config["altitude"];                                # km
@show proton_injection_config["thetamin"], proton_injection_config["thetamax"];  # downgoing
@show proton_injection_config["gamma"];                                   # CR-flux-shaped (~2.7)

# Run on a fresh frames container so we can compare side-by-side with the
# neutrino frames above without mutating them.
proton_frames = load_frames(geometry_file)
inject_protons!(proton_frames, proton_injection_config)

proton_frames                       # tree view: M frame + NEVENT Q frames

# Per-Q-frame keys: same skeleton as the neutrino case, but
#   - no `injection_close_state`  (no Earth-propagation cascade)
#   - new `particle_passes_through_rock`  (Bool: did the proton's trajectory
#     pass through rock before reaching the atmosphere?)
proton_q1 = proton_frames.q_frames[1]
sort(collect(keys(proton_q1.data)))

# initial_state lives at `altitude` km; final_state is at the surface where
# the shower starts:
proton_q1["injection_initial_state"].pdg            # 2212 (proton)
proton_q1["injection_initial_state"].position
proton_q1["injection_final_state"].position

# weight_params has the same struct shape, but the cross-section / column-
# depth fields are NaN — the surface-injection path doesn't fill them:
proton_wp = proton_q1["weight_params"]
proton_wp

# That NaN is also the discriminator the analysis code uses to pick the
# right one-weight formula (see TamboMakie.jl/src/plotting/effA.jl::get_p):
#
#     if isnan(wp.generated_xs)              # surface-injected
#         oneweight_per_event = 1 / p_mc_surface(wp)
#     else                                   # forced interaction
#         oneweight_per_event = p_phys(wp) / p_mc(wp)
#     end
#
# For protons there is no `p_phys` correction — every primary that gets
# sampled produces a shower, so the only weight is the inverse generation
# density. Divide by NEVENT for the per-generated-event normalization:

@doc Tambo.p_mc_surface

@show Tambo.p_mc_surface(proton_wp);

proton_oneweight = 1 / (Tambo.p_mc_surface(proton_wp) * NEVENT)
@show proton_oneweight;

# Multiplying by a cosmic-ray flux dN/(dE·dA·dt·dΩ) and an exposure time
# gives the expected proton event count, the same way the neutrino oneweight
# does for an astrophysical-neutrino flux.
