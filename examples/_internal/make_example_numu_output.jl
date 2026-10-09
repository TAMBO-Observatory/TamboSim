# make_example_numu_output.jl
#
# Produces examples/resources/example_numu_output.jld2 — a small, deterministic
# fixture of MuonNeutrinoInjection events used by test/test_run_corsika.jl to
# verify plan_corsika_jobs routing without relying on geometry luck.
#
# Pipeline mirrors 1_inject.jl: inject nu_mu CC events on the colca_valley_3000
# geometry (the committed test fixture), filter to events with a valid CC vertex,
# and save. thetamin=0 (includes downgoing) is required so that CC vertices land
# near the detector and hit the colca_valley BVH.
#
# Re-run when the on-disk schema changes or the geometry fixture changes.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using TamboSim
using TOML

const SEED   = 43   # offset by simset_id=1 as 1_inject.jl does (base 42 + 1)
const NEVENT = 20

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
out_file      = joinpath(tambo_path, "examples", "resources", "example_numu_output.jld2")

config = Dict{String,Any}(
    "strategy"    => "MuonNeutrinoInjection",
    "seed"        => SEED,
    "nevent"      => NEVENT,
    "pdg"         => 14,
    "gamma"       => 1.0,
    "emin"        => 1.0e6,
    "emax"        => 1.0e7,
    "thetamin"    => 0.0,
    "thetamax"    => 117.0,
    "phimin"      => 90.0,
    "phimax"      => 290.0,
    "xs_location" => joinpath(tambo_path, "resources", "cross_section_tables",
                              "cross_sections.h5:CSMS_nutau"),
)

frames = load_frames(geometry_file)
inject!(frames, config)
filter!(f -> haskey(f, "injection_final_state"), frames)

n_q = length(frames.q_frames)
n_q > 0 || error("No events with injection_final_state — check geometry or config")
println("Surviving Q frames: $n_q / $NEVENT")

mkpath(dirname(out_file))
save_frames(out_file, frames)

sz_kb = round(filesize(out_file) / 1024, digits=1)
println("Wrote $out_file")
println("  file size: $sz_kb KB")
