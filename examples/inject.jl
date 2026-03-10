tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

import Pkg
Pkg.activate(".")
Pkg.develop(path=tambo_path)

using ArgParse
using JLD2
using Tambo

function parse_commandline()
    s = ArgParseSettings(
        description = "Inject neutrino events into TAMBO simulation"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file"
            arg_type = String
            default = "$(tambo_path)/resources/configuration_examples/paper_config.toml"
        "--outfile", "-o"
            help = "Output JLD2 file path"
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

config_file = args["config"]
outfile = args["outfile"]
nevent = args["nevent"]
pdg = args["pdg"]
cut_failed = !args["no-cut"]

sim = Simulation(config_file)
sim.config["injection"]["nevent"] = nevent
sim.config["injection"]["pdg"] = pdg
if !isnothing(args["seed"])
    sim.config["injection"]["pinecone"] = args["seed"]
end

@show sim.config["injection"]["nevent"]
@show pdg
@show cut_failed

inject!(sim)

if cut_failed
    fxn(frame) = haskey(frame, "injection_final_state")
    cut_frames!(sim.results, fxn)
end

jldopen(outfile, "w") do file
    file["sim"] = sim
end
