#!/usr/bin/env julia
#
# tambo_shower test suite — muon survival calibration.
#
# Measures P(survive | E, X) — the probability that a muon of energy E
# traverses a column depth X of standard rock and exits still a muon — by
# Monte Carlo with PROPOSAL, the same muon-transport code tambo_shower
# itself uses in rock. Writes calibration/muon_survival.toml: a per-energy
# survival curve plus its 99% and 1% crossing depths.
#
# That table is what 4_assert.jl's Tier 2 muon-range check interpolates:
# a muon whose ray-cast rock depth gives P_survive > 99% must reach the
# observation mesh; one with P_survive < 1% must not; in between is the
# stochastic regime and is not asserted.
#
# This is a ONE-TIME calibration. Re-run only if the muon energies in the
# configs change, or PROPOSAL / its parametrizations are updated. Commit
# the resulting calibration/muon_survival.toml.
#
#   julia calibrate_muon_survival.jl
#
# TAMBO_PROPOSAL_TABLES must point at the PROPOSAL interpolation tables.
#
# Caveat: the calibration uses TamboSim's PROPOSAL configuration, which may
# differ slightly from the cut/parametrization settings CORSIKA's PROPOSAL
# integration uses inside tambo_shower. The check is a rough sanity bound
# with wide 1%/99% margins, so small parametrization differences wash out;
# it is not a precision comparison.

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))   # the TamboSim package env

using TamboSim
import PROPOSAL as PP
using TOML
using Printf

# --- settings --------------------------------------------------------------

const RHO_ROCK = 2.65            # g/cm^3 — CORSIKA StandardRock density
const MUON_PDG = 13

# Muon energies to calibrate (GeV). Must cover the muon configs' primaries:
# cr_muon_skimming is 10 TeV, cr_muon_skimming_100TeV is 100 TeV. The
# configs are near-monoenergetic, so the Tier 2 check matches a shower to
# the nearest calibrated energy.
const ENERGIES_GEV = [1.0e4, 1.0e5]

# Muons propagated per (energy, depth) sample. 1e4 resolves a 1% tail to
# ~10% relative error — adequate for interpolating the crossing depth.
const N_MUON = 10_000

# Rock column-depth scan, in km. Brackets P = 1% .. 99% for both energies
# (the transition sits near ~3 km at 10 TeV, ~5 km at 100 TeV).
const DEPTHS_KM = collect(0.5:0.5:12.0)

# Reproducibility.
const SEED = 20260520

# PROPOSAL cuts — kept consistent with the suite's neutrino-injection
# [proposal] block so the whole suite uses one PROPOSAL configuration.
const PROPOSAL_CONFIG = Dict{String,Any}(
    "ecut"          => -1,       # no absolute stochastic cut; v_cut governs
    "vcut"          => 1.0e-2,   # losses above 1% of E are sampled stochastically
    "do_continuous" => true,     # continuous randomization of sub-cut losses
)

# --- calibration -----------------------------------------------------------

"""
    survival_fraction(propagator, E_gev, depth_cm; n = N_MUON) -> Float64

Propagate `n` muons of total energy `E_gev` through `depth_cm` of standard
rock; return the fraction that reach the far side still a muon.

A muon "survives" if PROPOSAL propagates it the full `depth_cm` without
ranging out or decaying — i.e. its final propagated distance reaches the
target depth. A muon that stops short has ranged out (decay is negligible
at these energies but is excluded for completeness).
"""
function survival_fraction(propagator, E_gev, depth_cm; n = N_MUON)
    E_mev = E_gev * 1000.0
    survived = 0
    for _ in 1:n
        state = PP.ParticleState(
            PP.PARTICLE_TYPE_MUMINUS,
            0.0, 0.0, 0.0,            # position (cm)
            0.0, 0.0, 1.0,            # direction (+z)
            E_mev;                    # total energy (MeV)
            time = 0.0,
            propagated_distance = 0.0,
        )
        result = PP.propagate(propagator, state;
                              max_distance = depth_cm, min_energy = 0.0)
        final   = PP.get_final_state(result)
        reached = PP.get_propagated_distance(final) >= depth_cm * (1 - 1e-6)
        survived += (reached && !PP.has_decay(result)) ? 1 : 0
    end
    return survived / n
end

"""
    crossing_depth(depths, probs, target) -> Float64

First column depth (linearly interpolated) at which the survival curve
crosses `target`. The curve falls monotonically modulo Monte Carlo noise.
Returns `NaN` if the scan never crosses `target`.
"""
function crossing_depth(depths, probs, target)
    for i in 2:lastindex(probs)
        if (probs[i-1] - target) * (probs[i] - target) <= 0
            t = (target - probs[i-1]) / (probs[i] - probs[i-1])
            return depths[i-1] + t * (depths[i] - depths[i-1])
        end
    end
    return NaN
end

function main()
    haskey(ENV, "TAMBO_PROPOSAL_TABLES") ||
        error("TAMBO_PROPOSAL_TABLES is not set — needed for the PROPOSAL tables.")

    cfg = merge(PROPOSAL_CONFIG,
                Dict("tablespath" => ENV["TAMBO_PROPOSAL_TABLES"]))
    TamboSim.init_proposal(cfg)
    TamboSim.is_proposal_available() ||
        error("PROPOSAL is not available — cannot calibrate.")
    PP.set_random_seed(Int32(SEED))

    propagator = TamboSim._propagator_cache[(MUON_PDG, "StandardRock")]

    out = Dict{String,Any}()
    for E in ENERGIES_GEV
        @info "Calibrating muon survival" energy_GeV = E n_muon = N_MUON
        depths_gcm2 = Float64[]
        probs       = Float64[]
        for km in DEPTHS_KM
            depth_cm = km * 1.0e5
            p = survival_fraction(propagator, E, depth_cm)
            push!(depths_gcm2, depth_cm * RHO_ROCK)   # column depth, g/cm^2
            push!(probs, p)
            @printf("  E=%-8.0f GeV   X=%5.1f km   P_survive=%.3f\n", E, km, p)
        end

        d99 = crossing_depth(depths_gcm2, probs, 0.99)
        d01 = crossing_depth(depths_gcm2, probs, 0.01)
        @printf("  -> P=99%% at %.3e g/cm^2 (%.2f km);  P=1%% at %.3e g/cm^2 (%.2f km)\n",
                d99, d99 / RHO_ROCK / 1e5, d01, d01 / RHO_ROCK / 1e5)

        out[@sprintf("E_%.0fGeV", E)] = Dict{String,Any}(
            "energy_gev"        => E,
            "column_depth_gcm2" => depths_gcm2,
            "p_survive"         => probs,
            "depth_p99_gcm2"    => d99,   # P_survive = 99% — below this, must survive
            "depth_p01_gcm2"    => d01,   # P_survive =  1% — above this, must range out
        )
    end

    outdir = joinpath(@__DIR__, "calibration")
    mkpath(outdir)
    outfile = joinpath(outdir, "muon_survival.toml")
    open(outfile, "w") do io
        println(io, "# Muon survival probability vs standard-rock column depth.")
        println(io, "# Generated by calibrate_muon_survival.jl (PROPOSAL Monte Carlo).")
        println(io, "# Consumed by 4_assert.jl's Tier 2 muon-range check.")
        TOML.print(io, out)
    end
    @info "Wrote calibration table" outfile
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
