# 2_analyze_output.jl
#
# Analyze a TamboSim simulation output: cut failed events, compute one-weights
# for flux estimates, classify tau decay locations and products. Designed to be
# pasted into the REPL section by section.
#
# This file targets examples/resources/example_output.jld2 so it runs on a
# fresh checkout. With only 50 generated events, the resulting statistics
# (one-weight distribution, rock-vs-air ratios, decay classification) are
# noisy — for meaningful analysis, re-run after producing a larger output
# via templates/6_full_pipeline.jl.
#
# For frame-container and key-inheritance basics, see 1_frame_usage.jl.
#
# Topics covered:
#   1. Filtering events with cut_frames!
#   2. Computing one-weights for physical flux estimates
#   3. Determining whether the tau decayed in rock or air
#   4. Classifying decay-product flavor (EM / hadronic / muonic)

using LinearAlgebra
using Statistics
using Tambo
using Unitful: ustrip, @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
example_file  = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

frames = load_frames([geometry_file, example_file])

length(frames.q_frames)           # surviving Q frames in the example output

# =============================================================================
# 1. Filtering events with cut_frames!
# =============================================================================
# cut_frames!(frames, predicate) keeps Q frames where predicate returns true.
# G/C/D/M frames are always preserved. Any P (physics) descendants of a cut
# Q frame cascade out alongside their parent — though that doesn't activate
# here, since example_output has only M+Q. See cut_frames!'s docstring for
# the full semantics.

# @doc cut_frames!                # uncomment to read the docstring inline

n_before = length(frames.q_frames)
cut_frames!(frames, f -> haskey(f, "injection_final_state"))
cut_frames!(frames, f -> haskey(f, "proposal_final_state"))
q_frames = frames.q_frames

@show n_before length(q_frames)

# =============================================================================
# 2. One-weights for physical flux estimates
# =============================================================================
# Each Q frame carries weight_params, which inject! populates with the
# generation density p_mc evaluated at the event's energy and direction.
# The one-weight 1 / (p_mc * n_gen) gives the per-event volume in
# (energy × area × solid-angle) phase space.

n_gen = n_before  # generated count, before any cuts

oneweights = Float64[]
energies   = Float64[]

for f in q_frames
    wp = f["weight_params"]
    pmc = Tambo.p_mc(wp)
    ustrip_pmc = ustrip(u"GeV^-1 * m^-3 * sr^-1", pmc)
    (ustrip_pmc <= 0 || !isfinite(ustrip_pmc)) && continue
    push!(oneweights, 1.0 / (ustrip_pmc * n_gen))
    push!(energies, ustrip(u"GeV", wp.generated_initial_e))
end

length(oneweights)                # events with a valid weight
median(oneweights)                # GeV · m^3 · sr / event

# =============================================================================
# 3. Rock vs air decay
# =============================================================================
# A tau decay is "in air" if a ray from the decay vertex pointed radially
# outward never re-intersects the topography. Otherwise it decayed in rock.

gframe = frames.g_frames[end]

function outward_ray(position)
    ecef_dir = Direction(normalize(convert(ecefcoordinates, position).point),
                         ecefcoordinates)
    d = convert(position.coordinate_system, ecef_dir)
    return Ray(position, d)
end

function decayed_in_air(frame)
    haskey(frame, "proposal_final_state") || return false
    return isempty(intersect_all(gframe["bvh"], outward_ray(frame["proposal_final_state"].position)))
end

n_air  = count(decayed_in_air, q_frames)
n_rock = length(q_frames) - n_air
@show n_air n_rock

# =============================================================================
# 4. Decay-product flavor classification
# =============================================================================
# Tau decays produce a mix of leptons + hadrons. Sum decay-product energies
# by flavor (skipping neutrinos and muons), then label by the dominant
# component: EM (>80% e/γ), hadronic (otherwise with visible energy), or
# muonic (everything ended up in skipped leptonic channels — implies a
# μ ν ν branch leaving no visible shower energy).

const EM_PDGS   = Set([11, -11, 22])
const SKIP_PDGS = Set([12, 14, 16, -12, -14, -16, 13, -13])

function classify_decay(frame)
    haskey(frame, "proposal_decay_products") || return :no_decay
    products = frame["proposal_decay_products"]
    isempty(products) && return :no_decay
    em_e, had_e = 0.0, 0.0
    for p in products
        pdg = abs(Int(p.pdg))
        pdg in SKIP_PDGS && continue
        if pdg in EM_PDGS
            em_e += ustrip(u"GeV", p.energy)
        else
            had_e += ustrip(u"GeV", p.energy)
        end
    end
    total = em_e + had_e
    total == 0 && return :muonic
    return em_e / total > 0.8 ? :em : :hadronic
end

decay_types = classify_decay.(q_frames)
Dict(t => count(==(t), decay_types) for t in (:em, :hadronic, :muonic, :no_decay))

# A representative air-decay event, for poking at:
air_idx = findfirst(decayed_in_air, q_frames)
f = q_frames[air_idx]
@show f["event_id"] f["proposal_final_state"].energy
f["proposal_decay_products"]
