# 2_analyze_output.jl
#
# Analyze a TamboSim simulation output: filter to events where the tau decayed
# in air, compute one-weights for flux estimates, classify decay products.
# Designed to be pasted into the REPL section by section.
#
# This file targets examples/resources/example_output.jld2 so it runs on a
# fresh checkout.
#
# For frame-container and key-inheritance basics, see 1_frame_usage.jl.
#
# Topics covered:
#   1. Filtering to air decays with filter!
#   2. Computing one-weights (with units!) for physical flux estimates
#   3. Classifying decay-product flavor (EM / hadronic / muonic)

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using Statistics
using TamboSim
using Unitful: ustrip, @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
example_file  = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

frames = load_frames([geometry_file, example_file])

# A tau decay is "in air" if a ray shot from the decay vertex in the direction
# radially outward from the Earth's center never re-intersects the topography
# (BVH stored on the G frame). `TamboSim.is_above_topography` is the
# library helper for exactly this query.

function decayed_in_air(frame)
    haskey(frame, "proposal_final_state") || return false
    return is_above_topography(frame["proposal_final_state"], frame["bvh"])
end

# =============================================================================
# 1. Filtering to air decays with filter!
# =============================================================================
# TamboSim extends `Base.filter!` so it operates only on Q frames: a Q frame
# is kept if the predicate returns true; G/C/D/M frames are always preserved;
# any R (reconstructed) descendants of a cut Q frame are removed alongside their
# parent — though that doesn't activate here, since example_output has only M+Q.

# Note the `!`: in Julia, this notation denotes functions which modify their
# argument, rather than returning a modified copy.

# Pre-cut tally:
@show n_before     = length(frames.q_frames);
@show n_air_before = count(decayed_in_air, frames.q_frames);
@show n_rock_before = n_before - n_air_before;

filter!(decayed_in_air, frames)
q_frames = frames.q_frames;
@show length(q_frames);                  # should match n_air_before

# =============================================================================
# 2. One-weights for physical flux estimates
# =============================================================================
# `oneweights(tf)` returns a per-Q-frame "OneWeight" with units of
# GeV · m² · sr. Multiplying by a flux dN/(dE·dA·dt·dΩ) (units
# 1/(GeV·m²·s·sr)) and an exposure time (s) gives the expected event count
# for that flux model. Generation-count normalization is built in: the
# weights are scaled by the original injected `nevent`, so cutting frames
# upstream (as we did with `decayed_in_air`) doesn't bias the result.
#
# See 6_weighting_walkthrough.jl for what the weighting machinery is doing
# under the hood.

ows = oneweights(frames)
@show length(ows);                       # one per surviving Q frame
@show median(ows);                       # median OneWeight, with units


# We can use the `oneweights` to compute the rate of neutrino events 
# under a given choice of flux, for example:

"""
    Φ_nu(E)

IceCube astrophysical neutrino flux (per flavor):
Φ = 1.8e-18 (E / 100 TeV)^{-2.52} GeV^{-1} cm^{-2} s^{-1} sr^{-1}.
"""
function Φ_nu(E)
    γ = 2.52
    E0 = 100 * u"TeV"
    norm = 1.8e-18 * u"GeV^-1 * cm^-2 * s^-1 * sr^-1"
    return norm * (E / E0)^(-γ)
end

# You want to evaluate the flux at the energy from the `phase_space_point`, 
# i.e. the energy of the arriving neutrino.
fluxes = [ Φ_nu( f["phase_space_point"].E ) for f in frames.q_frames ]

# Then you can compute the rate! As you can see, it is a small number:
rates = fluxes .* ows .|> u"s^(-1)"
total_rate = sum( rates ) |> u"yr^(-1)"

# You can also compute the "error" in our calculation of the rate.
# This is quite large because our example injection did not have very many events in it.
total_rate_err = sqrt( sum(rates.^2) ) |> u"yr^(-1)"

# =============================================================================
# 3. Decay-product flavor classification
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

# A representative event, for poking at:
f = first(q_frames)
@show f["event_id"] f["proposal_final_state"].energy;
f["proposal_decay_products"]

# see TamboMakie.jl for visualization functions that would allow you to plot this event!
