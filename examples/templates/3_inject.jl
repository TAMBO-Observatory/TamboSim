# 3_inject.jl
#
# Sample primaries on a TamboSim geometry and write the resulting Q frames
# to disk. The injection backend is chosen by the `strategy` field in the
# `[injection]` TOML table:
#
#   strategy = "NeutrinoInjection"   → TauRunner Earth propagation +
#                                      forced CC interaction at the
#                                      detector. Default config:
#                                      tau_neutrino_cc.toml.
#
#   strategy = "CosmicRayInjection"  → surface injection at a
#                                      configurable altitude, no forced
#                                      interaction. Default config:
#                                      cosmic_ray_proton.toml.
#
# Input:
#   <geometry>.jld2     a GCD bundle from 1_create_geometry.jl (D frame may
#                       or may not have detector units placed; injection
#                       does not need them)
#   <config>.toml       injection settings — `strategy`, energy range,
#                       zenith range, n events, RNG seed (`seed`),
#                       primary PDG + cross-section table location
#                       (neutrino) or sampling `altitude` (proton).
#
# Output:
#   <outfile>.jld2      Q-frame stream containing one frame per sampled
#                       primary, with key `injection_final_state` (and a
#                       few siblings) populated. By default, frames whose
#                       injection failed (region not visible from the chosen
#                       direction) are dropped — pass `--no-cut` to keep them.
#
# CLI flags `--nevent`, `--pdg`, `--seed` override the corresponding TOML
# values (`seed` for the seed) so a single config can serve sweeps.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using TamboSim
using TOML

# =============================================================================
# Main
# =============================================================================

function parse_commandline()
    s = ArgParseSettings(
        description = "Inject primaries into a TAMBO simulation; backend selected by config[\"injection\"][\"strategy\"]"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file (default: tau_neutrino_cc.toml)"
            arg_type = String
            default = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
        "--geometry", "-g"
            help = "Path to geometry JLD2 file (produced by create_geometry.jl)"
            arg_type = String
            default = "$(tambo_path)/resources/geometry/colca_valley_3000.jld2"
        "--outfile", "-o"
            help = "Output JLD2 file path for simulation frames"
            arg_type = String
            default = "$(tambo_path)/examples/output/injected.jld2"
        "--nevent", "-n"
            help = "Number of events to simulate"
            arg_type = Int
            default = 100000
        "--pdg", "-p"
            help = "Override the primary PDG code in the config (e.g. 16=nutau, 14=numu, 2212=proton)"
            arg_type = Int
            default = nothing
        "--no-cut"
            help = "Disable cutting failed events (where injection region was not visible)"
            action = :store_true
        "--seed", "-s"
            help = "Random seed (overrides config seed value)"
            arg_type = Int
            default = nothing
    end

    return parse_args(s)
end

args = parse_commandline()

outfile    = args["outfile"]
cut_failed = !args["no-cut"]

config = TOML.parsefile(args["config"])
relativize!(config)

injection_config = config["injection"]
injection_config["nevent"] = args["nevent"]
if !isnothing(args["pdg"])
    injection_config["pdg"] = args["pdg"]
end
if !isnothing(args["seed"])
    injection_config["seed"] = args["seed"]
end

println("Injection settings:")
println("  strategy          : $(injection_config["strategy"])")
println("  primary PDG       : $(injection_config["pdg"])")
println("  n events to throw : $(injection_config["nevent"])")
println("  drop failed events: $cut_failed")

frames = load_frames(args["geometry"])
inject!(frames, injection_config)

if cut_failed
    filter!(frame -> haskey(frame, "injection_final_state"), frames)
end

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile  ($(count(f -> f.stream == 'Q', frames)) events)")
