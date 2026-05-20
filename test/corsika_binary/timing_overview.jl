#!/usr/bin/env julia
#
# tambo_shower test suite — timing overview.
#
# Reads each shower's summary.yaml and reports how long the CORSIKA jobs
# took — per config, overall, and the slowest individual showers. Not a
# test: a quick way to see whether the suite fits its runtime budget and
# which configs dominate. submit.slurm runs it automatically after Phase 4.
#
#   julia timing_overview.jl
#
# TAMBO_TEST_OUTDIR must point at a completed run's output.

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))   # the TamboSim package env

using YAML
using JSON3
using TOML
using Printf
using Statistics: median

const CONFIG_DIR = joinpath(@__DIR__, "configs")

# Format a duration in seconds as H:MM:SS.
function _hms(sec)
    s = round(Int, sec)
    h, rem = divrem(s, 3600)
    m, s   = divrem(rem, 60)
    return @sprintf("%d:%02d:%02d", h, m, s)
end

"""
    shower_runtimes(jobs_file) -> (done, no_summary)

`done` is a vector of `(outdir, runtime_seconds)` for every shower planned
in `jobs_file` that produced a readable summary.yaml; `no_summary` lists
the outdirs that did not (never ran, or crashed before writing it).
"""
function shower_runtimes(jobs_file)
    done       = Tuple{String,Float64}[]
    no_summary = String[]
    for line in eachline(jobs_file)
        isempty(strip(line)) && continue
        rec    = JSON3.read(line)
        outdir = String(rec.outdir)
        summ   = joinpath(outdir, "summary.yaml")
        if isfile(summ) && haskey(YAML.load_file(summ), "runtime_raw")
            push!(done, (outdir, Float64(YAML.load_file(summ)["runtime_raw"])))
        else
            push!(no_summary, outdir)
        end
    end
    return done, no_summary
end

function main()
    outdir = get(ENV, "TAMBO_TEST_OUTDIR", "")
    isempty(outdir) && error("TAMBO_TEST_OUTDIR is not set.")

    configs = sort(filter(f -> endswith(f, ".toml"),
                          readdir(CONFIG_DIR; join = true)))

    println("tambo_shower test suite — timing overview")
    println("="^72)

    all_times    = Tuple{String,Float64}[]   # (outdir, seconds) across configs
    n_no_summary = 0

    for c in configs
        name      = TOML.parsefile(c)["name"]
        jobs_file = joinpath(outdir, name, "jobs.jsonl")
        if !isfile(jobs_file)
            @printf("%-26s  (not planned)\n", name)
            continue
        end
        done, no_summary = shower_runtimes(jobs_file)
        n_no_summary += length(no_summary)
        if isempty(done)
            @printf("%-26s  no completed showers\n", name)
            continue
        end
        times = [t for (_, t) in done]
        append!(all_times, done)
        miss = isempty(no_summary) ? "" : @sprintf("  [%d missing]", length(no_summary))
        @printf("%-26s  showers: %2d   total: %9s   min/med/max: %.0f/%.0f/%.0f s%s\n",
                name, length(times), _hms(sum(times)),
                minimum(times), median(times), maximum(times), miss)
    end

    println("-"^72)
    if isempty(all_times)
        println("No completed showers found under $outdir.")
        return
    end

    grand = sum(t for (_, t) in all_times)
    @printf("%-26s  showers: %2d   total: %9s   (CPU time)\n",
            "TOTAL", length(all_times), _hms(grand))
    njobs = get(ENV, "TAMBO_SHOWER_JOBS", "")
    if !isempty(njobs)
        @printf("%-26s  wall-clock at %s-way parallelism ≈ %s\n",
                "", njobs, _hms(grand / parse(Float64, njobs)))
    end
    n_no_summary > 0 &&
        @printf("\n%d shower(s) wrote no summary.yaml — never ran or crashed.\n",
                n_no_summary)

    # Slowest individual showers.
    println("\nSlowest showers:")
    for (od, t) in first(sort(all_times; by = x -> x[2], rev = true), 5)
        @printf("  %7.0f s   %s\n", t, relpath(od, outdir))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
