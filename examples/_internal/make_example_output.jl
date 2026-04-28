# make_example_output.jl
#
# Produces examples/resources/example_output.jld2 — a small, deterministic
# pipeline output used by examples/interactive/1_frame_usage.jl as the file
# that script loads and explores.
#
# Pipeline: inject 50 nu_tau CC events on the colca_valley_3000 geometry,
# cut failed injections, run PROPOSAL propagation, cut events whose final
# state ended up inside rock. CORSIKA is not invoked — the artifact stays
# fully reproducible without depending on the tambo_shower binary.
#
# The output is committed to git. Re-run when the on-disk schema changes
# (in which case 1_frame_usage.jl probably needs updating too).

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using LinearAlgebra
using Tambo
using TOML

const SEED   = 1234
const NEVENT = 50

config_file   = joinpath(tambo_path, "resources", "configuration_examples", "tau_neutrino_cc.toml")
geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
out_file      = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

config = TOML.parsefile(config_file)
relativize!(config)

config["injection"]["nevent"]   = NEVENT
config["injection"]["pinecone"] = SEED
config["proposal"]["pinecone"]  = SEED

frames = load_frames(geometry_file)
inject!(frames, config["injection"])
cut_frames!(frames, f -> haskey(f, "injection_final_state"))

proposal_propagation!(frames, config["proposal"])
gframe = frames.g_frames[end]

function upray(particle)
    d = Direction(
        normalize(convert(ecefcoordinates, particle.position)),
        ecefcoordinates
    )
    d = convert(particle.position.coordinate_system, d)
    return Ray(particle.position, d)
end
isinair(particle) = isempty(intersect_all(gframe["bvh"], upray(particle)))
cut_frames!(frames, f -> isinair(f["proposal_final_state"]))

mkpath(dirname(out_file))
save_frames(out_file, frames)

n_q   = length(frames.q_frames)
sz_kb = round(filesize(out_file) / 1024, digits=1)
println("Wrote $out_file")
println("  surviving Q frames: $n_q")
println("  file size:          $sz_kb KB")
