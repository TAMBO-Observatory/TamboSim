# 4_propagation_walkthrough.jl
#
# Run proposal_propagation! after inject! and explore what PROPOSAL does
# to each event. Designed to be pasted into the REPL section by section —
# values display themselves rather than being wrapped in println.
#
# This walkthrough produces the same data as
# examples/resources/example_output.jld2 (it uses the same seed, event
# count, and configuration as _internal/make_example_output.jl).
#
# For frame-container basics, see 1_frame_usage.jl. For what inject! does
# upstream, see 3_injection_walkthrough.jl.
#
# Topics covered:
#   1. Prereqs: an injected TamboFrames + the [proposal] TOML table
#   2. PROPOSAL backend init via init_proposal
#   3. The per-event call: proposal_propagate(particle, prem, bvh, seed)
#   4. Inspecting one event's outputs: losses, continuous_e, decay products,
#      final state
#   5. The 106 MeV skip threshold and its effect on the surviving frames
#   6. Diff against post-injection: which keys are new

using Tambo
using TOML
using Unitful: ustrip, @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
config_file   = joinpath(tambo_path, "resources", "configuration_examples", "tau_neutrino_cc.toml")

const SEED   = 1234
const NEVENT = 50

# =============================================================================
# 1. Prereqs: a frames container with injection_final_state populated
# =============================================================================
# proposal_propagation! needs an existing M frame (so call it after inject!)
# and operates on Q frames that contain `injection_final_state`. Cutting
# failed injections first is conventional — those frames have no input
# state for PROPOSAL anyway.

config = TOML.parsefile(config_file)
relativize!(config)

config["injection"]["nevent"]   = NEVENT
config["injection"]["pinecone"] = SEED
config["proposal"]["pinecone"]  = SEED

frames = load_frames(geometry_file)
inject!(frames, config["injection"])
cut_frames!(frames, f -> haskey(f, "injection_final_state"))

@show length(frames.q_frames);      # surviving events after the injection cut

# What the [proposal] table looks like:
proposal_config = config["proposal"]
keys(proposal_config) |> collect |> sort
proposal_config["pinecone"]         # RNG seed (already overridden above)

# =============================================================================
# 2. PROPOSAL backend init
# =============================================================================
# init_proposal reads the cross-section tables on disk and builds two
# cached propagators per lepton: one for rock, one for air. The cache
# survives across calls, so subsequent proposal_propagation! invocations
# are cheap. proposal_propagation! calls init_proposal for you, but you
# can call it eagerly if you want to inspect or warm the cache.

@doc Tambo.init_proposal

# =============================================================================
# 3. Per-event call: proposal_propagate
# =============================================================================
# proposal_propagation! loops over Q frames and calls the lower-level
# proposal_propagate on the input state. The inner function does the
# segment-by-segment work: it ray-traces the particle's trajectory
# against PREM + topography to get a sequence of (length, density) pieces,
# then steps PROPOSAL through each segment with the appropriate medium
# (rock or air) and accumulates losses, secondaries, and the final state.

@doc Tambo.proposal_propagate

# Run the high-level wrapper now — this is the point at which Q frames
# gain their proposal_* keys.
proposal_propagation!(frames, proposal_config)

# =============================================================================
# 4. Inspecting one event's outputs
# =============================================================================
# proposal_propagation! writes four keys per event:
#
#   proposal_stochastic_losses   Vector{Particle} — discrete losses (brems,
#                                pair-production, hadronic, decay-tagged)
#   proposal_continuous_losses   total continuous (ionization) energy lost
#   proposal_decay_products      Vector{Particle} — daughters from decay,
#                                empty if the lepton ranged out without
#                                decaying
#   proposal_final_state         Particle — the lepton at the end of its
#                                tracked path (decay vertex or trajectory
#                                exit)

q = first(filter(f -> haskey(f, "proposal_final_state"), frames.q_frames))

q["injection_final_state"]          # input to PROPOSAL: tau at interaction vertex
q["proposal_final_state"]           # output: tau at decay vertex (or end of track)

@show q["injection_final_state"].energy |> u"PeV";
@show q["proposal_final_state"].energy  |> u"PeV";  # generally lower — energy lost along the track
@show q["proposal_continuous_losses"]   |> u"PeV";  # how much went into ionization

losses = q["proposal_stochastic_losses"]
@show length(losses);               # number of discrete losses logged
isempty(losses) || losses[1]        # one example loss (Particle struct)

products = q["proposal_decay_products"]
@show length(products);             # nonzero if the tau decayed in flight

# =============================================================================
# 5. The 106 MeV skip threshold
# =============================================================================
# proposal_propagation! has a hardcoded guard at propagation.jl:177:
# frames whose injection_final_state energy falls below 106 MeV are
# silently skipped — proposal_propagate is never called and none of the
# four proposal_* keys get written. 106 MeV is just above muon rest mass
# (105.66 MeV), so it works as a low-energy floor for muon and tau
# tracking; both species effectively never hit it at TAMBO energies.
#
# We're not tracking electrons with PROPOSAL at this time; if that
# changes, this guard will need to be revisited (106 MeV is far above
# the regime where electron propagation should still matter).

n_total      = length(frames.q_frames)
n_propagated = count(f -> haskey(f, "proposal_final_state"), frames.q_frames)
n_skipped    = n_total - n_propagated

@show n_total n_propagated n_skipped;

# =============================================================================
# 6. Diff against post-injection
# =============================================================================
# Comparing the keys present on a propagated Q frame vs. the post-injection
# state from 3_injection_walkthrough.jl:
#
#   added by proposal_propagation!:
#     proposal_stochastic_losses
#     proposal_continuous_losses
#     proposal_decay_products
#     proposal_final_state

sort(collect(keys(q.data)))         # event_id, injection_*, weight_params, proposal_*

# The M frame also gained a snapshot of the proposal config:
mframe = frames.m_frames[end]
sort(collect(keys(mframe.data)))    # ["injection", "proposal"]

# Continue with 5_corsika_walkthrough.jl to see how the proposal_decay_products
# get fed into CORSIKA to simulate the resulting air showers.
