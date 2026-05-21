# 6_corsika_hits.jl
#
# Read the per-event CORSIKA output directories produced by 5_run_corsika.jl
# and project each surviving shower particle onto the detector OBBs in the
# D frame. Thin wrapper around `read_corsika_hits!`.
#
# Input:
#   <geometry>.jld2     GCD bundle containing detector units in the D frame
#                       (`detector_unit_bvh`) — produced by running
#                       2_create_detector.jl on the output of
#                       1_create_geometry.jl
#   <infile>.jld2       Q-frame stream from 5_run_corsika.jl, where each
#                       Q frame carries `corsika_directories` listing the
#                       per-shower output dirs `corsika_run!` dispatched
#
# Output:
#   <outfile>.jld2      the same Q-frame stream with a new key
#                       `corsika_hits`: a Vector of NamedTuples
#                       (particle, module_index, weight), one per hit

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
        description = "Project CORSIKA shower particles onto detector OBBs and record hits"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file (provides default --geometry)"
            arg_type = String
            default = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
        "--geometry", "-g"
            help = "Path to GCD bundle JLD2 with detector units placed (from 2_create_detector.jl). Overrides config[\"geometry\"][\"geometry_path\"]."
            arg_type = String
            default = nothing
        "--infile", "-i"
            help = "Input JLD2 with CORSIKA-ready frames (from 5_run_corsika.jl)"
            arg_type = String
            default = "$(tambo_path)/examples/output/corsika_ready.jld2"
        "--outfile", "-o"
            help = "Output JLD2 file path (defaults to overwriting --infile)"
            arg_type = String
            default = ""
    end

    return parse_args(s)
end

args = parse_commandline()

infile        = args["infile"]
outfile       = isempty(args["outfile"]) ? infile : args["outfile"]

config = TOML.parsefile(args["config"])
relativize!(config)
geometry_file = something(args["geometry"], config["geometry"]["geometry_path"])

frames = load_frames([geometry_file, infile])
read_corsika_hits!(frames)

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile")
