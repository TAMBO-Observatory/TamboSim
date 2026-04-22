tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using ArgParse
using LinearAlgebra
using Tambo

function parse_commandline()
    s = ArgParseSettings(
        description = "Propagate leptons through TAMBO geometry using PROPOSAL"
    )

    @add_arg_table! s begin
        "--infile", "-i"
            help = "Input JLD2 file with injected Q frames"
            arg_type = String
            default = "$(tambo_path)/examples/output/injected_events.jld2"
        "--gc-file"
            help = "GC frames JLD2 file (defaults to gc_frames.jld2 in same directory as infile)"
            arg_type = String
            default = nothing
        "--outfile", "-o"
            help = "Output JLD2 file path for Q frames"
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

infile        = args["infile"]
gc_file       = something(args["gc-file"], joinpath(dirname(infile), "gc_frames.jld2"))
outfile       = args["outfile"]
cut_inmountain = args["cut-inmountain"]

@show infile
@show gc_file
@show outfile
@show cut_inmountain

frames = load_frames([gc_file, infile])

if !isnothing(args["seed"])
    get_frame(frames, 'C')["proposal"]["pinecone"] = args["seed"]
end

proposal_propagation!(frames)

@show count(f -> f.stream == 'Q', frames)

if cut_inmountain
    earth = get_earth(frames)

    function upray(particle)
        d = Direction(
            normalize(convert(ecefcoordinates, particle.position)),
            ecefcoordinates
        )
        d = convert(particle.position.coordinate_system, d)
        return Ray(particle.position, d)
    end

    isinair(particle) = isempty(intersect_all(earth, upray(particle)))
    cut_frames!(frames, frame -> isinair(frame["proposal_final_state"]))
end

@show count(f -> f.stream == 'Q', frames)

mkpath(dirname(outfile))
save_frames(outfile, frames)  # Q frames only (default)
println("Q frames → $outfile")
