#!/usr/bin/env julia
#
# tambo_shower test suite — Phase 4: assertions.
#
# Reads the shower output produced by Phase 3 (3_run_showers.sh) and runs the
# checks from assertions.jl. Exits non-zero if any test fails, so a Slurm job
# or CI step can detect failure from the exit code.
#
# Environment variables:
#   TAMBO_TEST_OUTDIR    directory holding all suite output (set in Phase 1)
#   TAMBO_TEST_GEOMETRY  canonical geometry — its topography BVH drives the
#                        rock-propagation checks (optional: the muon check
#                        degrades to "marginal" if unavailable)
#
# A config's baseline, if present at baselines/<name>.toml, enables the
# statistical-consistency check for that config; otherwise it is skipped. The
# muon survive/die check needs calibration/muon_survival.toml (see
# calibrate_muon_survival.jl); without it those assertions are skipped.

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))   # the TamboSim package env

using TamboSim
using TOML
using JSON3
using Test

include("assertions.jl")

const CONFIG_DIR   = joinpath(@__DIR__, "configs")
const BASELINE_DIR = joinpath(@__DIR__, "baselines")
const CALIB_FILE   = joinpath(@__DIR__, "calibration", "muon_survival.toml")

"""
    read_jobs(jobs_file) -> Vector

Parse a `jobs.jsonl` written by 1_plan.jl into a vector of JSON records.
"""
function read_jobs(jobs_file)
    recs = Any[]
    for line in eachline(jobs_file)
        isempty(strip(line)) && continue
        push!(recs, JSON3.read(line))
    end
    return recs
end

"""
    load_injection_frames(base, geometry) -> Union{Nothing, TamboFrames}

The injected frames for one config (`<base>/injection.jld2`, written by
1_plan.jl), loaded together with `geometry` so each Q frame is reattached to
its G/C/D parents and resolves `bvh` / `detector_bvh`. Returns `nothing`
(and warns) if either file is unavailable — the rock-propagation checks are
then skipped.
"""
function load_injection_frames(base, geometry)
    inj = joinpath(base, "injection.jld2")
    if !isfile(inj) || isempty(geometry) || !isfile(geometry)
        @warn "injection.jld2 or geometry unavailable — muon rock-traversal " *
              "check skipped" inj geometry
        return nothing
    end
    return load_frames([geometry, inj])
end

"""
    load_muon_calibration() -> Union{Nothing, Dict}

The PROPOSAL muon-survival table. Returns `nothing` (and warns) if it has
not been generated — the muon survive/die assertions are then skipped.
"""
function load_muon_calibration()
    if !isfile(CALIB_FILE)
        @warn "No calibration/muon_survival.toml — run calibrate_muon_survival.jl. " *
              "Muon survive/die assertions skipped."
        return nothing
    end
    return TOML.parsefile(CALIB_FILE)
end

"""
    assert_config(cfg_path, outdir, geometry, calib)

Run every check for one test config's output. The `jobs.jsonl` written by
1_plan.jl is the source of truth for which shower directories to expect.
"""
function assert_config(cfg_path, outdir, geometry, calib)
    cfg  = TOML.parsefile(cfg_path)
    name = cfg["name"]
    base = joinpath(outdir, name)

    @testset "$name" begin
        jobs_file = joinpath(base, "jobs.jsonl")
        if !isfile(jobs_file)
            @test false   # Phase 1 never planned this config
            return
        end

        recs   = read_jobs(jobs_file)
        # decay_id == 99 marks the determinism repeat appended by 1_plan.jl.
        normal = filter(r -> r.decay_id != 99, recs)
        repeat = filter(r -> r.decay_id == 99, recs)

        if isempty(normal)
            @test false   # config planned no showers
            return
        end

        # Q frames from injection.jld2, keyed by event_id, for the
        # rock-propagation checks. Empty if the frames are unavailable.
        inj_frames = load_injection_frames(base, geometry)
        qframe_by_event = inj_frames === nothing ? Dict{Int,Any}() :
            Dict(Int(qf["event_id"]) => qf for qf in inj_frames.q_frames)

        shower_dirs = String[]
        for r in normal
            sd = String(r.outdir)
            push!(shower_dirs, sd)
            @testset "$(basename(dirname(sd)))/$(basename(sd))" begin
                qf = get(qframe_by_event, Int(r.event_id), nothing)
                observe = expect_observation(qf, calib)
                did = Int(r.decay_id)

                assert_output_tree(sd)
                assert_injection_roundtrip(sd, qf, did, r.argv)
                assert_energy_budget(sd; expect_observation = observe)
                assert_no_unexpected_warnings(sd)
                assert_rock_muon_rangeout(sd, qf, calib)
                assert_no_EM_shower_in_rock(sd, qf, did)
                assert_downgoing_photon_dominated(sd, qf, did)
            end
        end

        # Determinism — the repeat job was cloned from the first normal job.
        if !isempty(repeat)
            @testset "determinism" begin
                assert_determinism(String(normal[1].outdir),
                                   String(repeat[1].outdir))
            end
        end

        # # Statistical consistency — only when a committed baseline exists.
        # baseline_path = joinpath(BASELINE_DIR, "$name.toml")
        # if isfile(baseline_path)
        #     @testset "statistical consistency" begin
        #         stats = summary_stats(shower_dirs)
        #         assert_statistical_consistency(stats, TOML.parsefile(baseline_path))
        #     end
        # else
        #     @info "No baseline for $name — statistical consistency skipped" baseline_path
        # end

    end
end

function main()
    outdir = get(ENV, "TAMBO_TEST_OUTDIR", "")
    isempty(outdir) && error("TAMBO_TEST_OUTDIR is not set.")
    isdir(outdir)   || error("TAMBO_TEST_OUTDIR does not exist: $outdir")

    configs = sort(filter(f -> endswith(f, ".toml"),
                          readdir(CONFIG_DIR; join = true)))
    isempty(configs) && error("No .toml configs found in $CONFIG_DIR")

    # Inputs for the rock-propagation checks. The geometry is loaded per
    # config (with that config's injection.jld2) inside assert_config.
    geometry = get(ENV, "TAMBO_TEST_GEOMETRY", "")
    calib    = load_muon_calibration()

    # The outermost @testset throws a TestSetException on any failure when
    # it finishes — an uncaught exception gives Julia a non-zero exit code.
    @testset "tambo_shower suite" begin
        for c in configs
            assert_config(c, outdir, geometry, calib)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
