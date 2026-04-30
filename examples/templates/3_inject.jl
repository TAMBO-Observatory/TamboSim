# 3_inject.jl
#
# Sample primaries on a TamboSim geometry and write the resulting Q frames
# to disk. Two modes:
#
#   default          neutrino injection via `inject!` — TauRunner Earth
#                    propagation + forced CC interaction at the detector.
#                    Reads `[injection]` from a neutrino TOML (default:
#                    tau_neutrino_cc.toml).
#
#   --protons        cosmic-ray proton injection via `inject_protons!` —
#                    surface injection at a configurable altitude, no
#                    forced interaction. Reads `[injection]` from a
#                    proton TOML (default: cosmic_ray_proton.toml). The
#                    `--pdg` flag is ignored in this mode.
#
# Input:
#   <geometry>.jld2     a GCD bundle from 1_create_geometry.jl (D frame may
#                       or may not have detector units placed; injection
#                       does not need them)
#   <config>.toml       injection settings — energy range, zenith range,
#                       n events, RNG seed (`pinecone`), and (neutrino only)
#                       primary PDG + cross-section table location, or
#                       (proton only) sampling `altitude`.
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
using TamboSim
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
            help = "Path to configuration TOML file (default selected from --protons)"
            arg_type = String
            default = nothing
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
            help = "Particle PDG code (e.g., 16 for nutau, 14 for numu); ignored with --protons"
            arg_type = Int
            default = 16
        "--protons"
            help = "Inject downgoing cosmic-ray protons via inject_protons! instead of inject!"
            action = :store_true
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

outfile        = args["outfile"]
inject_protons = args["protons"]
cut_failed     = !args["no-cut"]

default_config = inject_protons ? "cosmic_ray_proton.toml" : "tau_neutrino_cc.toml"
config_path    = something(args["config"],
                           "$(tambo_path)/resources/configuration_examples/$default_config")

config = TOML.parsefile(config_path)
relativize!(config)

injection_config = config["injection"]
injection_config["nevent"] = args["nevent"]
if !inject_protons
    injection_config["pdg"] = args["pdg"]
end
if !isnothing(args["seed"])
    injection_config["pinecone"] = args["seed"]
end

println("Injection settings:")
println("  mode              : $(inject_protons ? "cosmic-ray protons" : "neutrinos")")
if !inject_protons
    println("  primary PDG       : $(injection_config["pdg"])")
end
println("  n events to throw : $(injection_config["nevent"])")
println("  drop failed events: $cut_failed")

frames = load_frames(args["geometry"])
if inject_protons
    inject_protons!(frames, injection_config)
else
    inject!(frames, injection_config)
end

if cut_failed
    filter!(frame -> haskey(frame, "injection_final_state"), frames)
end

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile  ($(count(f -> f.stream == 'Q', frames)) events)")
