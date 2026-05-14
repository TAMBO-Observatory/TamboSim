# 5_run_corsika.jl
#
# Run CORSIKA 8 (`tambo_shower`) on the decay products from PROPOSAL,
# producing one event directory per Q frame under `--corsika-dir`. Wraps
# `corsika_run`, which reads its settings from the `[corsika]` table of a
# configuration TOML (binary path, energy cuts, hadronic model, mesh paths,
# `seed` seed, optional `sbatch_command` for cluster submission).
#
# Input:
#   <geometry>.jld2     GCD bundle (provides topography mesh + detector
#                       region used to compute the trajectory→surface
#                       intercept)
#   <infile>.jld2       Q-frame stream from 4_propagate.jl, containing
#                       `proposal_decay_products`
#
# Output:
#   <corsika-dir>/      one subdirectory per event (named `event_<id>/`),
#                       written by tambo_shower itself
#   <outfile>.jld2      the same Q-frame stream with the `[corsika]` config
#                       stored on the M frame for downstream provenance
#
# Note: this script only orchestrates `tambo_shower` — it does not project
# the resulting shower particles onto detector modules. That second pass is
# 6_corsika_hits.jl, which reads the per-event directories produced here.
# For real-scale runs, set `sbatch_command` in the TOML and submit on a
# cluster; running `corsika_run` from a Julia driver is mainly useful for
# small test runs.

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
        description = "Run CORSIKA 8 (tambo_shower) on PROPOSAL decay products"
    )

    @add_arg_table! s begin
        "--config", "-c"
            help = "Path to configuration TOML file (for corsika settings)"
            arg_type = String
            default = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
        "--geometry", "-g"
            help = "Path to geometry JLD2 file (provides G + D frames). Overrides config[\"geometry\"][\"geometry_path\"]."
            arg_type = String
            default = nothing
        "--infile", "-i"
            help = "Input JLD2 with propagated frames (from 4_propagate.jl)"
            arg_type = String
            default = "$(tambo_path)/examples/output/propagated.jld2"
        "--outfile", "-o"
            help = "Output JLD2 file path"
            arg_type = String
            default = "$(tambo_path)/examples/output/corsika_ready.jld2"
        "--corsika-dir", "-d"
            help = "Directory for tambo_shower per-event output dirs"
            arg_type = String
            default = "$(tambo_path)/examples/output/corsika"
        "--seed", "-s"
            help = "Random seed (overrides config seed value)"
            arg_type = Int
            default = nothing
    end

    return parse_args(s)
end

args = parse_commandline()

infile        = args["infile"]
outfile       = args["outfile"]
corsika_dir   = args["corsika-dir"]

config = TOML.parsefile(args["config"])
relativize!(config)
geometry_file = something(args["geometry"], config["geometry"]["geometry_path"])

println("CORSIKA run settings:")
println("  infile         : $infile")
println("  outfile        : $outfile")
println("  per-event dirs : $corsika_dir")

corsika_config = config["corsika"]
if !isnothing(args["seed"])
    corsika_config["seed"] = args["seed"]
end

if !isfile(corsika_config["corsika_path"])
    error("tambo_shower binary not found at $(corsika_config["corsika_path"]) — " *
          "build it first (see resources/corsika/src/BUILD.md)")
end

frames = load_frames([geometry_file, infile])
corsika_run(frames, corsika_config, corsika_dir)

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile")
println("CORSIKA event dirs → $corsika_dir")
