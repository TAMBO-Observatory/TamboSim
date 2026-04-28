"""
analyze_simulation.jl

Demonstrates how to work with Tambo simulation output stored in JLD2 files.
Covers the common analysis patterns:

  1. Loading frames and iterating events
  2. Accessing particle states and weight parameters
  3. Cutting events that failed injection
  4. Computing one-weights for physical flux estimates
  5. Determining whether the tau decayed in rock or air
  6. Inspecting decay products

Expected input: a JLD2 file produced by inject! + proposal_propagation!,
saved with save_frames.
"""

using LinearAlgebra
using Statistics
using Tambo
using Unitful: ustrip, @u_str

gc_path  = joinpath(@__DIR__, "output", "gc_frames.jld2")
sim_path = joinpath(@__DIR__, "output", "simulation_proposal.jld2")

frames = load_frames([gc_path, sim_path])
q_frames = filter(f -> f.stream == 'Q', frames)
println("Loaded $(length(q_frames)) event frames from $sim_path")

# =============================================================================
# 1. Accessing frame variables
# =============================================================================
# Each Q frame is a hierarchical dict. Keys are written by inject! and
# proposal_propagation! using their outprefix arguments (default: "injection"
# and "proposal"). Every frame has an event_id set at creation time.

frame = first(q_frames)
println("\n--- Frame keys ---")
println(collect(keys(frame)))

println("\n--- Event $(frame["event_id"]) ---")
println("  initial neutrino energy : ", frame["injection_initial_state"].energy)

if haskey(frame, "injection_final_state")
    tau = frame["injection_final_state"]
    println("  tau energy at vertex    : ", tau.energy)
    println("  tau PDG                 : ", tau.pdg)
end

# =============================================================================
# 2. Cutting events that did not pass injection
# =============================================================================
n_before = length(q_frames)
filter!(frame -> haskey(frame, "injection_final_state"), frames)
filter!(frame -> haskey(frame, "proposal_final_state"), frames)
q_frames = filter(f -> f.stream == 'Q', frames)
println("\nAfter cuts: $(length(q_frames)) / $n_before events pass")

# =============================================================================
# 3. Computing one-weights
# =============================================================================
n_gen = n_before

oneweights = Float64[]
energies   = Float64[]

for frame in q_frames
    wp = frame["weight_params"]
    pmc = Tambo.p_mc(wp)
    ustrip_pmc = ustrip(u"GeV^-1 * m^-3 * sr^-1", pmc)
    (ustrip_pmc <= 0 || !isfinite(ustrip_pmc)) && continue
    push!(oneweights, 1.0 / (ustrip_pmc * n_gen))
    push!(energies, ustrip(u"GeV", wp.generated_initial_e))
end

println("\nOne-weight statistics (units: GeV m^3 sr / event):")
println("  n events with valid weight : $(length(oneweights))")
isempty(oneweights) || println("  median one-weight          : $(round(median(oneweights), sigdigits=3))")

# =============================================================================
# 4. Rock vs air decay
# =============================================================================
g_frame = Tambo._get_last_frame(frames, 'G')

function outward_ray(position)
    ecef_dir = Direction(normalize(convert(ecefcoordinates, position).point),
                         ecefcoordinates)
    d = convert(position.coordinate_system, ecef_dir)
    return Ray(position, d)
end

function decayed_in_air(frame)
    haskey(frame, "proposal_final_state") || return false
    return isempty(intersect_all(g_frame["bvh"], outward_ray(frame["proposal_final_state"].position)))
end

n_air  = count(decayed_in_air, q_frames)
n_rock = length(q_frames) - n_air
println("\nDecay location:")
println("  air decays  : $n_air")
println("  rock decays : $n_rock")

# =============================================================================
# 5. Inspecting decay products
# =============================================================================
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
println("\nDecay type classification:")
for t in (:em, :hadronic, :muonic, :no_decay)
    println("  $t : $(count(==(t), decay_types))")
end

air_idx = findfirst(decayed_in_air, q_frames)
if !isnothing(air_idx)
    frame = q_frames[air_idx]
    println("\nFirst air-decay event (event_id=$(frame["event_id"])):")
    println("  tau final energy : ", frame["proposal_final_state"].energy)
    for (i, p) in enumerate(frame["proposal_decay_products"])
        println("  product $i: pdg=$(p.pdg)  energy=$(round(ustrip(u"GeV", p.energy), sigdigits=4)) GeV")
    end
end
