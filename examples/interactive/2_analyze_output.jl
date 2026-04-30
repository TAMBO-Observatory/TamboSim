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

using Statistics
using Tambo
using Unitful: ustrip, @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
example_file  = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

frames = load_frames([geometry_file, example_file])

# A tau decay is "in air" if a ray shot radially outward from the decay
# vertex never re-intersects the topography (BVH stored on the G frame).
# `Tambo.is_above_topography` is the library helper for exactly this query.

function decayed_in_air(frame)
    haskey(frame, "proposal_final_state") || return false
    return is_above_topography(frame["proposal_final_state"], frame["bvh"])
end

# =============================================================================
# 1. Filtering to air decays with filter!
# =============================================================================
# Tambo extends `Base.filter!` so it operates only on Q frames: a Q frame
# is kept if the predicate returns true; G/C/D/M frames are always preserved;
# any P (physics) descendants of a cut Q frame cascade out alongside their
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
# Each Q frame carries weight_params, which inject! populates with the
# generation phase-space + forced-interaction information. Two densities
# are read off it:
#
#   p_mc(wp)     generation density (GeV^-1 · m^-3 · sr^-1) — power-law,
#                solid angle, area, and the forced-interaction factors
#                that focused events on the detector.
#   p_phys(wp)   physical interaction density (m^-1) — the natural rate
#                at which the close_state would have interacted at the
#                forced vertex.
#
# Forcing interactions inflated each event's MC weight; dividing by p_mc
# and multiplying by p_phys is the importance-sampling correction that
# puts you back on the natural physical rate. Per-event normalization is
# 1 / n_gen:
#
#     oneweight = (p_phys(wp) / p_mc(wp)) / n_gen
#
# Units come out to GeV · m² · sr / event — the standard "OneWeight"
# shape. Multiplying by a flux dN/(dE·dA·dt·dΩ) (units 1/(GeV·m²·s·sr))
# and an exposure time (s) gives the expected event count.
#
# Units stay attached throughout — Unitful does the bookkeeping, and the
# REPL display tells you what you're looking at.

n_gen = n_before  # generated count, before any cuts

wps   = [f["weight_params"] for f in q_frames]
pmcs  = [Tambo.p_mc(wp)   for wp in wps]
pphys = [Tambo.p_phys(wp) for wp in wps]

# Filter to events with a finite, positive generation density:
valid_idx = findall(p -> isfinite(ustrip(p)) && ustrip(p) > 0, pmcs)

oneweights = [(pphys[i] / pmcs[i]) / n_gen for i in valid_idx]   # GeV · m² · sr / event
energies   = [wps[i].generated_initial_e for i in valid_idx]      # GeV

@show length(oneweights);
@show median(oneweights);                # the median one-weight, with units

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