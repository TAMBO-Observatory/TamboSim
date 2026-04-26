tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using ArgParse
using LinearAlgebra
using Tambo
using TOML

function parse_commandline()
    s = ArgParseSettings(
        description = "Propagate leptons through TAMBO geometry using PROPOSAL"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file (for proposal settings)"
            arg_type = String
            default = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
        "--geometry", "-g"
            help = "Path to geometry JLD2 file (provides G frame)"
            arg_type = String
            default = "$(tambo_path)/resources/geometry/colca_valley_3000.jld2"
        "--infile", "-i"
            help = "Input JLD2 file with injected frames"
            arg_type = String
            default = "$(tambo_path)/examples/output/simulation_injection.jld2"
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

geometry_file  = args["geometry"]
infile         = args["infile"]
outfile        = args["outfile"]
cut_inmountain = args["cut-inmountain"]

@show infile
@show outfile
@show cut_inmountain

config = TOML.parsefile(args["config"])
relativize!(config)

proposal_config = config["proposal"]
if !isnothing(args["seed"])
    proposal_config["pinecone"] = args["seed"]
end

frames = load_frames([geometry_file, infile])
proposal_propagation!(frames, proposal_config)

@show count(f -> f.stream == 'Q', frames)

if cut_inmountain
    gframe = get_frame(frames, 'G')

    function upray(particle)
        d = Direction(
            normalize(convert(ecefcoordinates, particle.position)),
            ecefcoordinates
        )
        d = convert(particle.position.coordinate_system, d)
        return Ray(particle.position, d)
    end

    isinair(particle) = isempty(intersect_all(gframe["bvh"], upray(particle)))
    cut_frames!(frames, frame -> isinair(frame["proposal_final_state"]))
end

@show count(f -> f.stream == 'Q', frames)

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile")
