# 4_propagate.jl
#
# Propagate the leptons produced by injection through the rock+air geometry
# using PROPOSAL. Wraps `proposal_propagation!`, which reads its settings
# from the `[proposal]` table of a configuration TOML.
#
# Input:
#   <geometry>.jld2     GCD bundle (provides the G frame: BVH, PREM layers,
#                       coordinate system)
#   <infile>.jld2       Q-frame stream from 3_inject.jl, containing
#                       `injection_final_state` per event
#
# Output:
#   <outfile>.jld2      Q frames extended with `proposal_final_state` (the
#                       lepton at the end of its tracked path) and
#                       `proposal_decay_products` (daughter particles, when
#                       the lepton decays in flight)
#
# Optional `--cut-inmountain` drops events whose `proposal_final_state` ends
# below the topography surface — i.e. the lepton ranged out inside rock and
# will not produce an air shower. The `upray`/`isinair` helper that
# implements this lives inline; it shoots a vertical ray from the particle
# position and asks whether the topography BVH sits above it.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using LinearAlgebra
using Tambo
using TOML

# =============================================================================
# Main
# =============================================================================

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
            default = "$(tambo_path)/examples/output/injected.jld2"
        "--outfile", "-o"
            help = "Output JLD2 file path"
            arg_type = String
            default = "$(tambo_path)/examples/output/propagated.jld2"
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

println("Propagation settings:")
println("  infile           : $infile")
println("  outfile          : $outfile")
println("  drop in-mountain : $cut_inmountain")

config = TOML.parsefile(args["config"])
relativize!(config)

proposal_config = config["proposal"]
if !isnothing(args["seed"])
    proposal_config["pinecone"] = args["seed"]
end

frames = load_frames([geometry_file, infile])
proposal_propagation!(frames, proposal_config)

println("After propagation: $(count(f -> f.stream == 'Q', frames)) Q frames")

if cut_inmountain
    g_frame = Tambo._get_last_frame(frames, 'G')

    function upray(particle)
        d = Direction(
            normalize(convert(ecefcoordinates, particle.position)),
            ecefcoordinates
        )
        d = convert(particle.position.coordinate_system, d)
        return Ray(particle.position, d)
    end

    isinair(particle) = isempty(intersect_all(g_frame["bvh"], upray(particle)))
    filter!(frame -> isinair(frame["proposal_final_state"]), frames)
end

println("After in-mountain cut: $(count(f -> f.stream == 'Q', frames)) Q frames")

mkpath(dirname(outfile))
save_frames(outfile, frames)
println("Saved → $outfile")
