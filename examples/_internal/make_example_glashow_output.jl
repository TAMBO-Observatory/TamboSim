# make_example_glashow_output.jl
#
# Produces examples/resources/example_glashow_output.jld2 — a small, deterministic
# fixture of GlashowInjection events used by test/test_run_corsika.jl and
# test/test_glashow.jl.
#
# Pipeline mirrors make_example_output.jl: inject ν̄_e Glashow events on the
# colca_valley_3000 geometry, keep events with a τ⁻ final state, then run PROPOSAL
# so the τ decay products are present. CORSIKA is not invoked.
#
# Re-run when the on-disk schema changes or the geometry fixture changes.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using TamboSim
using TOML

const SEED   = 4321
const NEVENT = 30

config_file   = joinpath(tambo_path, "resources", "configuration_examples", "glashow_nuebar.toml")
geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
out_file      = joinpath(tambo_path, "examples", "resources", "example_glashow_output.jld2")

config = TOML.parsefile(config_file)
relativize!(config)
config["injection"]["nevent"] = NEVENT
config["injection"]["seed"]   = SEED
config["proposal"]["seed"]    = SEED

frames = load_frames(geometry_file)
inject!(frames, config["injection"])
filter!(f -> haskey(f, "injection_final_state"), frames)
proposal_propagation!(frames, config["proposal"])

n_q = length(frames.q_frames)
n_q > 0 || error("No events with injection_final_state — check geometry or config")

mkpath(dirname(out_file))
save_frames(out_file, frames)

sz_kb = round(filesize(out_file) / 1024, digits=1)
println("Wrote $out_file")
println("  surviving Q frames: $n_q / $NEVENT")
println("  file size:          $sz_kb KB")
