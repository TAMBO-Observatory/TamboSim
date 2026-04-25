tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using ArgParse
using Tambo
using TOML

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
            default = "$(tambo_path)/examples/output/injected_events.jld2"
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

@show injection_config["nevent"]
@show injection_config["pdg"]
@show cut_failed

frames = load_frames(args["geometry"])
inject!(frames, injection_config)

if cut_failed
    cut_frames!(frames, frame -> haskey(frame, "injection_final_state"))
end

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile  ($(count(f -> f.stream == 'Q', frames)) events)")
