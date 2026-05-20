#!/usr/bin/env julia
#
# tambo_shower test suite — Phase 4: assertions.
#
# Reads the shower output produced by Phase 3 (3_run_showers.sh) and runs the
# tiered checks from assertions.jl. Exits non-zero if any test fails, so a
# Slurm job or CI step can detect failure from the exit code.
#
# Environment variables:
#   TAMBO_TEST_OUTDIR    directory holding all suite output (set in Phase 1)
#   TAMBO_TEST_GEOMETRY  canonical geometry — its topography BVH drives the
#                        Tier 2 muon rock-traversal check (optional: the
#                        check degrades to "marginal" if unavailable)
#
# A config's regression baseline, if present at baselines/<name>.toml,
# enables Tier 4b for that config; otherwise Tier 4b is skipped. The muon
# survive/die check needs calibration/muon_survival.toml (see
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
    load_topography_bvh() -> Union{Nothing, BVHTree}

Topography BVH from the canonical geometry, for the Tier 2 muon
rock-traversal check. Returns `nothing` (and warns) if the geometry is
unavailable — the muon check then degrades to "marginal".
"""
function load_topography_bvh()
    geom = get(ENV, "TAMBO_TEST_GEOMETRY", "")
    if isempty(geom) || !isfile(geom)
        @warn "TAMBO_TEST_GEOMETRY unavailable — muon rock-traversal check degraded."
        return nothing
    end
    frames = load_frames(geom)
    return frames.g_frames[end]["bvh"]
end

"""
    load_muon_calibration() -> Union{Nothing, Dict}

The PROPOSAL muon-survival table. Returns `nothing` (and warns) if it has
not been generated — Tier 2 muon survive/die assertions are then skipped.
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
    assert_config(cfg_path, outdir, bvh, calib)

Run every tier for one test config's output. The `jobs.jsonl` written by
1_plan.jl is the source of truth for which shower directories to expect.
"""
function assert_config(cfg_path, outdir, bvh, calib)
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

        shower_dirs = String[]
        for r in normal
            sd = String(r.outdir)
            push!(shower_dirs, sd)
            @testset "$(basename(dirname(sd)))/$(basename(sd))" begin
                # Predict a muon's fate through the terrain rock; this gates
                # whether Tier 2 expects anything at the observation mesh.
                pred = muon_rock_prediction(r, bvh, calib)
                expect_mesh = !pred.applies || pred.outcome == :survives

                assert_tier1_smoke(sd)
                assert_tier2_physics(sd; expect_at_mesh = expect_mesh)
                assert_tier3_geometry(sd)
                pred.applies && assert_muon_survival(sd, pred)
            end
        end

        # Tier 4a — the repeat job was cloned from the first normal job.
        if !isempty(repeat)
            @testset "Tier 4a determinism" begin
                assert_tier4a_determinism(String(normal[1].outdir),
                                          String(repeat[1].outdir))
            end
        end

        # Tier 4b — regression, only when a committed baseline exists.
        baseline_path = joinpath(BASELINE_DIR, "$name.toml")
        if isfile(baseline_path)
            @testset "Tier 4b regression" begin
                stats = summary_stats(shower_dirs)
                assert_tier4b_regression(stats, TOML.parsefile(baseline_path))
            end
        else
            @info "No baseline for $name — Tier 4b skipped" baseline_path
        end
    end
end

function main()
    outdir = get(ENV, "TAMBO_TEST_OUTDIR", "")
    isempty(outdir) && error("TAMBO_TEST_OUTDIR is not set.")
    isdir(outdir)   || error("TAMBO_TEST_OUTDIR does not exist: $outdir")

    configs = sort(filter(f -> endswith(f, ".toml"),
                          readdir(CONFIG_DIR; join = true)))
    isempty(configs) && error("No .toml configs found in $CONFIG_DIR")

    # Shared inputs for the Tier 2 muon rock-traversal check.
    bvh   = load_topography_bvh()
    calib = load_muon_calibration()

    # The outermost @testset throws a TestSetException on any failure when
    # it finishes — an uncaught exception gives Julia a non-zero exit code.
    @testset "tambo_shower suite" begin
        for c in configs
            assert_config(c, outdir, bvh, calib)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
