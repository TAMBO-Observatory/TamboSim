"""
analyze_simulation.jl

Demonstrates how to work with Tambo simulation output stored in JLD2 files.
Covers the common analysis patterns:

  1. Loading a simulation and iterating frames
  2. Accessing particle states and weight parameters
  3. Cutting events that failed injection
  4. Computing one-weights for physical flux estimates
  5. Determining whether the tau decayed in rock or air
  6. Inspecting decay products

Expected input: a JLD2 file produced by inject! + proposal_propagation!,
saved as file["sim"] = sim.
"""

using JLD2
using LinearAlgebra
using Tambo
using Unitful: ustrip, @u_str

sim_path = joinpath(@__DIR__, "output", "simulation_proposal.jld2")

sim = jldopen(sim_path) do f
    f["sim"]
end
println("Loaded $(length(sim.results)) frames from $sim_path")

# =============================================================================
# 1. Accessing frame variables
# =============================================================================
# Each frame is a hierarchical dict. Keys are written by inject! and
# proposal_propagation! using their outprefix arguments (default: "injection"
# and "proposal"). Every frame has an event_id set at creation time.

frame = first(sim.results)
println("\n--- Frame keys ---")
println(collect(keys(frame)))

# Particle states written by inject!:
#   injection_initial_state  — neutrino at the interaction vertex
#   injection_final_state    — tau lepton produced (absent if injection failed)
#   injection_close_state    — tau closest approach to detector (if computed)
#
# Weight parameters (always present after inject!):
#   weight_params            — sampling ranges, generated energy, cross-sections

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
# inject! only writes injection_final_state when the neutrino successfully
# interacted and produced a tau inside the Earth. Events without this key
# are failed injection attempts and carry no physics information.

n_before = length(sim.results)
cut_frames!(sim.results, frame -> haskey(frame, "injection_final_state"))
println("\nAfter injection cut: $(length(sim.results)) / $n_before events pass")

# Also require that propagation ran (proposal_final_state present)
cut_frames!(sim.results, frame -> haskey(frame, "proposal_final_state"))
println("After propagation cut: $(length(sim.results)) events with propagated tau")

# =============================================================================
# 3. Computing one-weights
# =============================================================================
# p_mc(wp) gives the Monte Carlo phase space density for the generated event.
# The one-weight 1/p_mc is proportional to the physical flux per generated
# event. Sum one-weights to get an effective area; divide by a physical flux
# model to get an event rate.
#
# Units: p_mc has units of GeV^-1 m^-3 sr^-1, so 1/p_mc has units of
# GeV m^3 sr. Multiply by n_gen to get m^2 sr (effective area in GeV bin).

n_gen = n_before

oneweights = Float64[]
energies   = Float64[]

for frame in sim.results
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
# After proposal_propagation!, the tau either decayed underground (rock) or
# after emerging into the atmosphere (air). Cast a ray from the final state
# position pointing radially outward. If that ray has no terrain intersections,
# the position is above the surface — an air decay. Otherwise it is still
# underground — a rock decay.

earth = Earth(
    sim.config["geometry"]["earth_path"],
    sim.config["geometry"]["detector_key"],
)

function outward_ray(position)
    ecef_dir = Direction(normalize(convert(ecefcoordinates, position).point),
                         ecefcoordinates)
    d = convert(position.coordinate_system, ecef_dir)
    return Ray(position, d)
end

function decayed_in_air(frame)
    haskey(frame, "proposal_final_state") || return false
    ray = outward_ray(frame["proposal_final_state"].position)
    return isempty(intersect_all(earth, ray))
end

n_air  = count(decayed_in_air, sim.results)
n_rock = length(sim.results) - n_air
println("\nDecay location:")
println("  air decays  : $n_air")
println("  rock decays : $n_rock")

# =============================================================================
# 5. Inspecting decay products
# =============================================================================
# proposal_propagation! stores the tau's decay products under
# proposal_decay_products. Each product is a Particle with pdg, energy,
# position, and direction.

const EM_PDGS   = Set([11, -11, 22])           # e±, γ
const SKIP_PDGS = Set([12, 14, 16, -12, -14, -16, 13, -13])  # ν, μ

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

decay_types = classify_decay.(sim.results)
println("\nDecay type classification:")
for t in (:em, :hadronic, :muonic, :no_decay)
    println("  $t : $(count(==(t), decay_types))")
end

# Example: print a summary of the first air-decay event's products
air_idx = findfirst(decayed_in_air, sim.results)
if !isnothing(air_idx)
    frame = sim.results[air_idx]
    println("\nFirst air-decay event (event_id=$(frame["event_id"])):")
    println("  tau final energy : ", frame["proposal_final_state"].energy)
    for (i, p) in enumerate(frame["proposal_decay_products"])
        println("  product $i: pdg=$(p.pdg)  energy=$(round(ustrip(u"GeV", p.energy), sigdigits=4)) GeV")
    end
end
