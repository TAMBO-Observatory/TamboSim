tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

import Pkg
Pkg.activate(".")
Pkg.develop(path=tambo_path)

using ArgParse
using JLD2
using LinearAlgebra
using Tambo

function parse_commandline()
    s = ArgParseSettings(
        description = "Propagate leptons through TAMBO geometry using PROPOSAL"
    )

    @add_arg_table! s begin
        "--infile", "-i"
            help = "Input JLD2 file with injected events"
            arg_type = String
            default = "$(tambo_path)/examples/output/injected_events.jld2"
        "--outfile", "-o"
            help = "Output JLD2 file path"
            arg_type = String
            default = "$(tambo_path)/examples/output/propagated_events.jld2"
        "--cut-inmountain"
            help = "Cut events where final state is inside the mountain"
            action = :store_true
        "--seed", "-s"
            help = "Random seed (overrides config pinecone value)"
            arg_type = Int
            default = nothing
    end

    return parse_args(s)
end

args = parse_commandline()

infile = args["infile"]
outfile = args["outfile"]
cut_inmountain = args["cut-inmountain"]

@show infile
@show outfile
@show cut_inmountain

sim = jldopen(infile) do file
    file["sim"]
end

if !isnothing(args["seed"])
    sim.config["proposal"]["pinecone"] = args["seed"]
end

# uncomment if cut not performed in previous step
# injection_succeeded(frame) = haskey(frame, "injection_final_state")
# cut_frames!(sim.results, injection_succeeded)

proposal_propagation!(sim)

@show length(sim.results)
if cut_inmountain
    earth = Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )
    function upray(particle, earth)
        d = Direction(
            normalize(convert(ecefcoordinates, particle.position)),
            ecefcoordinates
        )
        d = convert(particle.position.coordinate_system, d)
        ray = Ray(particle.position, d)
        return ray
    end
    isinair(particle) = length(intersect_all(earth, upray(particle, earth)))==0
    fxn(frame) = isinair(frame["proposal_final_state"])
    cut_frames!(sim.results, fxn)
end
@show length(sim.results)

jldopen(outfile, "w") do file
    file["sim"] = sim
end
