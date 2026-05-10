# 3_injection_walkthrough.jl
#
# Run injection from scratch on the canonical Colca-valley geometry and
# explore what it does to a TamboFrames container. Designed to be pasted
# into the REPL section by section — values display themselves rather
# than being wrapped in println.
#
# The public entrypoint is `inject!(frames, config)`, which reads
# `config["strategy"]` and dispatches to one of the backends:
#
#   "NeutrinoInjection"  → inject_neutrinos!
#   "CosmicRayInjection" → inject_protons!
#
# This walkthrough calls the backends directly (sections 2 and 7) so the
# per-strategy mechanics are explicit; in production scripts, prefer
# `inject!(frames, config)` and let the strategy field route the work.
#
# This walkthrough produces (modulo the missing PROPOSAL stage) the same
# data that examples/resources/example_output.jld2 carries, by using the
# same seed and event count as _internal/make_example_output.jl.
#
# For frame-container basics, see 1_frame_usage.jl.
#
# Topics covered:
#   1. Inputs to inject_neutrinos!: the geometry G frame + the [injection] TOML table
#   2. Run inject_neutrinos! and survey the result (M frame + Q frames + new keys)
#   3. The samplers and cross section that did the per-event work
#   4. The three injection states and how the sampling inversion sets them
#   5. phase_space_point — the per-event handoff to the weighting walkthrough
#   6. Failure mode: when an injected direction doesn't see any rock
#   7. Variant: inject_protons! for cosmic-ray primaries

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using TamboSim
using TOML
using Unitful: @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
config_file   = joinpath(tambo_path, "resources", "configuration_examples", "tau_neutrino_cc.toml")

const SEED   = 1234
const NEVENT = 50

# =============================================================================
# 1. Inputs to inject_neutrinos!
# =============================================================================
# inject_neutrinos! takes a TamboFrames container (must contain a G frame)
# and a parsed [injection] config dict. It mutates the container: pushing
# one new M frame + nevent new Q frames.

@doc TamboSim.inject_neutrinos!

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
# 2. Run inject_neutrinos! and survey the result
# =============================================================================
# A single inject_neutrinos! call does two things internally:
#   (a) appends one M frame to the container, snapshotted under the
#       "injection" key, plus `nevent` empty Q frames each tagged with a
#       sequential event_id;
#   (b) loops over those Q frames, sampling and tracing each event, and
#       writes injection_*_state + phase_space_point onto each frame.
# Sections 3–5 unpack what (b) put where; this section just runs the
# call and shows the resulting shape.

TamboSim.inject_neutrinos!(frames, injection_config)

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
sort(collect(keys(q1.data)))        # event_id, injection_*_state, phase_space_point

# =============================================================================
# 3. The samplers and cross section that did the per-event work
# =============================================================================
# The per-event loop in inject_neutrinos! draws from three machines, all configured
# from the [injection] table:
#
#   UnitfulPowerLawSampler     energy ∈ [emin, emax] GeV with dN/dE ∝ E^-gamma
#   UniformAngularSampler      direction uniformly in the zenith/azimuth box
#   CrossSection               neutrino-nucleon σ(E) interpolated from a table
#
# These don't survive on the frames after inject_neutrinos! returns, so to inspect
# them we re-construct a copy here — these are the same constructors inject_neutrinos! uses
# internally.

@doc TamboSim.UnitfulPowerLawSampler

@doc TamboSim.UniformAngularSampler

# The cross-section table that ships with the canonical config:
xs = TamboSim.CrossSection(injection_config["xs_location"])
xs                                  # struct fields show the energy grid + σ values

# =============================================================================
# 4. The three injection states
# =============================================================================
# inject_neutrino_event uses a sampling-inversion trick to focus events on the
# detector. Rather than throwing primaries on a sphere far from the
# mountain (most would miss), it:
#
#   (1) draws a direction d from the specified angular range,
#   (2) samples a point p on the detector-region surface (weighted by
#       triangle area and its visibility along d),
#   (3) ray-traces the *reverse* direction back through PREM + topography
#       to find the trajectory that would arrive at p, d,
#   (4) hands that trajectory to TauRunner, which propagates a virtual
#       primary along it through Earth and reports what survives at p,
#   (5) forces a CC interaction inside the rock leading up to p, producing
#       a tau at the interaction vertex.
#
# The three saved states correspond to steps (3), (4), (5):
#
#   injection_close_state     the *physical* state arriving at p with
#                             direction d, with meaningful position, direction,
#                             and energy. in a tau neutrino injection, 
#                             this state is returned by TauRunner and can be 
#                             either a neutrino (typically) or a tau. 
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
#   injection_final_state     if a neutrino interaction had to be forced,
#                             this state corresponds to the forced CC 
#                             interaction vertex inside rock — a physically 
#                             distinct point along the trajectory leading to p, 
#                             where close_state is forced to interact. Otherwise
#                             this is just final_state === close_state.
#
# Frames whose sampling step (2) found no visible detector triangle, or
# whose back-traced trajectory failed to validate, lack *_final_state —
# see Section 6.

q1["injection_initial_state"]       # bookkeeping: source-side energy attached to p
q1["injection_close_state"]         # TauRunner output; usually a neutrino at p
q1["injection_final_state"]         # forced CC vertex (or === close_state if tau out)

# For events where TauRunner returns a neutrino that survived the full
# trajectory, initial and close share position+direction; the only
# difference is the energy. That energy gap is the Earth-absorption
# cascade: at PeV+ the CC mean free path through rock is short, so much
# of the source-side energy is lost in the integrated column depth.
# TauRunner samples that loss; (initial.energy / close.energy) gives
# the per-event suppression.
q1["injection_initial_state"].energy |> u"PeV"
q1["injection_close_state"].energy |> u"PeV"

# close → final is a CC interaction: final.energy = (1 - y) * close.energy
# where y is the Bjorken inelasticity (typically tens of percent at PeV).
q1["injection_final_state"].energy |> u"PeV"

q1["injection_initial_state"].pdg    # 16 (nu_tau)
q1["injection_close_state"].pdg      # 16 if it survived as a neutrino; ±15 if regenerated as a tau
q1["injection_final_state"].pdg      # 15 (tau) — either the forced-CC outgoing tau or === close_state

# In this event, TauRunner ran all the way to p and returned a neutrino,
# so the initial and close positions are the same.
q1["injection_initial_state"].position == q1["injection_close_state"].position

# final lives elsewhere — at the point the neutrino interaction was 
# forced inside rock
q1["injection_final_state"].position


# =============================================================================
# 5. phase_space_point — the per-event handoff to the weighting walkthrough
# =============================================================================
# Successful events also receive a `phase_space_point` key — a small struct
# carrying the per-event coordinates (E, θ, φ, area, and for forced-CC
# events the column depth, density, and cross sections) that the weighting
# layer needs to assign each event a flux-independent one-weight.
#
# The shape of that struct, the campaign-level metadata it pairs with, and
# the formula `oneweights(tf)` applies are covered in 6_weighting_walkthrough.jl.
# Here we just confirm the key is present:

q1["phase_space_point"]             # struct fields display

# =============================================================================
# 6. Failure mode: directions that miss the detector region
# =============================================================================
# Some sampled directions never see the detector region at all (they go
# off into space without hitting rock that contains it). For those frames
# inject_neutrino_event skipped *_final_state and phase_space_point — only event_id
# remains. Downstream stages need the final state, so the templates cut
# these frames immediately:
#
#     filter!(frame -> haskey(frame, "injection_final_state"), frames)

n_total  = length(frames.q_frames)
n_failed = count(f -> !haskey(f, "injection_final_state"), frames.q_frames)
n_air    = n_total - n_failed

@show n_total n_failed n_air;

# This walkthrough stops short of the cut so you can still inspect a
# failed frame side-by-side with a successful one:
failed_q = first(filter(f -> !haskey(f, "injection_final_state"), frames.q_frames))
sort(collect(keys(failed_q.data)))  # event_id alone — no injection_*_state, no phase_space_point

# Continue with 4_propagation_walkthrough.jl to see what proposal_propagation!
# does with the surviving injection_final_state.

# =============================================================================
# 7. Variant: inject_protons! for cosmic-ray primaries
# =============================================================================
# Cosmic-ray protons are surface-injected: every primary produces a shower
# by construction, so there's no forced CC interaction, no Earth-propagation
# cascade, and no cross-section table. inject_protons! shares the same
# spectrum + angular samplers as inject_neutrinos!, but the per-event work
# and the resulting Q-frame keys are different.

@doc TamboSim.inject_protons!

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
TamboSim.inject_protons!(proton_frames, proton_injection_config)

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

# Protons get a `phase_space_point` too — a `SurfaceCRPoint` rather than
# the forced-CC variant the neutrino path produced. Surface CRs aren't
# forced to interact (every primary produces a shower), so the point only
# carries the source-side phase-space coordinates; the weighting layer
# dispatches on its type to pick the right per-event density.
proton_q1["phase_space_point"]

# As with neutrinos, see 6_weighting_walkthrough.jl for what `oneweights(tf)`
# does with these points.
