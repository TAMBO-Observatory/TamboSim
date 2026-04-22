tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using ArgParse
using Tambo

function parse_commandline()
    s = ArgParseSettings(
        description = "Inject neutrino events into TAMBO simulation"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file"
            arg_type = String
            default = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
        "--outfile", "-o"
            help = "Output JLD2 file path for Q frames"
            arg_type = String
            default = "$(tambo_path)/examples/output/injected_events.jld2"
        "--gc-file"
            help = "Output JLD2 file path for GC frames (defaults to gc_frames.jld2 in same directory as outfile)"
            arg_type = String
            default = nothing
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

outfile  = args["outfile"]
gc_file  = something(args["gc-file"], joinpath(dirname(outfile), "gc_frames.jld2"))
cut_failed = !args["no-cut"]

frames = load_config(args["config"])
cframe = get_frame(frames, 'C')
cframe["injection"]["nevent"] = args["nevent"]
cframe["injection"]["pdg"]    = args["pdg"]
if !isnothing(args["seed"])
    cframe["injection"]["pinecone"] = args["seed"]
end

@show cframe["injection"]["nevent"]
@show cframe["injection"]["pdg"]
@show cut_failed

mkpath(dirname(outfile))
save_frames(gc_file, frames; streams=('G', 'C'))

inject!(frames)

if cut_failed
    cut_frames!(frames, frame -> haskey(frame, "injection_final_state"))
end

save_frames(outfile, frames)  # Q frames only (default)
println("GC frames → $gc_file")
println("Q frames  → $outfile  ($(count(f -> f.stream == 'Q', frames)) events)")
