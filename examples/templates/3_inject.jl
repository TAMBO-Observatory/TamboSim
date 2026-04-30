# 3_inject.jl
#
# Sample neutrino primaries on a Tambo geometry and write the resulting Q
# frames to disk. Wraps `inject!`, which reads its parameters from the
# `[injection]` table of a configuration TOML.
#
# Input:
#   <geometry>.jld2     a GCD bundle from 1_create_geometry.jl (D frame may
#                       or may not have detector units placed; injection
#                       does not need them)
#   <config>.toml       injection settings — energy range, zenith range,
#                       primary PDG, n events, RNG seed (`pinecone`)
#
# Output:
#   <outfile>.jld2      Q-frame stream containing one frame per sampled
#                       primary, with key `injection_final_state` (and a
#                       few siblings) populated. By default, frames whose
#                       injection failed (region not visible from the chosen
#                       direction) are dropped — pass `--no-cut` to keep them.
#
# CLI flags `--nevent`, `--pdg`, `--seed` override the corresponding TOML
# values (`pinecone` for the seed) so a single config can serve sweeps.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using Tambo
using TOML

# =============================================================================
# Main
# =============================================================================

function parse_commandline()
    s = ArgParseSettings(
        description = "Inject neutrino events into TAMBO simulation"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file"
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
            help = "Particle PDG code (e.g., 16 for nutau, 14 for numu)"
            arg_type = Int
            default = 16
        "--no-cut"
            help = "Disable cutting failed events (where injection region was not visible)"
            action = :store_true
        "--seed", "-s"
            help = "Random seed (overrides config pinecone value)"
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
injection_config["pdg"]    = args["pdg"]
if !isnothing(args["seed"])
    injection_config["pinecone"] = args["seed"]
end

println("Injection settings:")
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
