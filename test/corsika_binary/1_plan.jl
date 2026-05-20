#!/usr/bin/env julia
#
# tambo_shower test suite — Phase 1: prerequisites, injection, planning.
#
# For each configs/*.toml this script:
#   1. checks that the binary, geometry, and PROPOSAL tables are in place;
#   2. loads the GCD geometry, injects primaries (inject!), and — for the
#      neutrino strategy — propagates the tau (proposal_propagation!);
#   3. plans every CORSIKA job and writes its argv to <outdir>/<name>/jobs.jsonl.
#
# Phase 3 (3_run_showers.sh) replays the argv; Phase 4 (4_assert.jl) checks the
# output. This script mirrors the pipeline's 1_inject.jl + 2_plan_showers.jl.
#
# Environment variables (see README.md):
#   TAMBO_SHOWER_BIN       path to the tambo_shower executable
#   TAMBO_TEST_GEOMETRY    path to the GCD geometry bundle (.jld2)
#   TAMBO_PROPOSAL_TABLES  Julia-side PROPOSAL tables dir (tau propagation)
#   TAMBO_TEST_OUTDIR      directory for all suite output
#   CORSIKA_DATA           (optional) binary-side data dir; PROPOSAL tables
#                          are expected at $CORSIKA_DATA/PROPOSAL

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))   # the TamboSim package env

using TamboSim
using TOML
using JSON3

const CONFIG_DIR = joinpath(@__DIR__, "configs")

# --------------------------------------------------------------------------
# Prerequisites
# --------------------------------------------------------------------------

env_or_error(key, what) = begin
    v = get(ENV, key, "")
    isempty(v) && error("$key is not set — required for $what. See " *
                         "test/corsika_binary/README.md")
    v
end

"""
    check_prerequisites() -> NamedTuple

Fail fast — before any injection or shower — if the binary, geometry, or
PROPOSAL tables are missing. A missing PROPOSAL table set silently turns a
test run into a multi-hour table build, so it is an error here, not a
surprise later.
"""
function check_prerequisites()
    shower_bin = env_or_error("TAMBO_SHOWER_BIN", "the tambo_shower binary")
    isfile(shower_bin) || error("TAMBO_SHOWER_BIN is not a file: $shower_bin")

    geometry = env_or_error("TAMBO_TEST_GEOMETRY", "the GCD geometry bundle")
    isfile(geometry) || error("TAMBO_TEST_GEOMETRY does not exist: $geometry")

    # Julia-side PROPOSAL tables — used by proposal_propagation! for tau
    # propagation in the neutrino-injection case.
    jl_tables = env_or_error("TAMBO_PROPOSAL_TABLES", "Julia-side PROPOSAL tables")
    (isdir(jl_tables) && !isempty(readdir(jl_tables))) || error(
        "TAMBO_PROPOSAL_TABLES is missing or empty: $jl_tables\n" *
        "Generate the PROPOSAL tables before running the suite.")

    # Binary-side PROPOSAL tables — tambo_shower resolves these via
    # corsika_data(\"PROPOSAL\") = \$CORSIKA_DATA/PROPOSAL (CorsikaData.inl).
    cdata = get(ENV, "CORSIKA_DATA", "")
    if isempty(cdata)
        @warn "CORSIKA_DATA is not set — tambo_shower will use its build-baked " *
              "PROPOSAL path. If those tables are missing the binary rebuilds " *
              "them on first run (very slow!). Point CORSIKA_DATA at a populated, " *
              "writable tables directory to avoid this."
    else
        pdir = joinpath(cdata, "PROPOSAL")
        (isdir(pdir) && !isempty(readdir(pdir))) || error(
            "CORSIKA_DATA/PROPOSAL is missing or empty: $pdir")
    end

    outdir = env_or_error("TAMBO_TEST_OUTDIR", "the suite output directory")
    mkpath(outdir)

    return (; shower_bin, geometry, outdir)
end

# --------------------------------------------------------------------------
# Per-config planning
# --------------------------------------------------------------------------

"""
    _set_f_flag(argv, outdir) -> Vector{String}

Return a copy of `argv` with the value following `-f` replaced by `outdir`.
Used to retarget the determinism-repeat job at its own output directory.
"""
function _set_f_flag(argv, outdir)
    out = collect(String, argv)
    i = findfirst(==("-f"), out)
    i === nothing && error("argv has no -f flag: $argv")
    out[i + 1] = outdir
    return out
end

"""
    plan_one(config_path, env)

Inject and plan a single test config; write its `jobs.jsonl`. Returns the
number of shower jobs written (excluding any determinism repeat).
"""
function plan_one(config_path, env)
    cfg  = TOML.parsefile(config_path)
    name = cfg["name"]
    base_outdir = joinpath(env.outdir, name)
    mkpath(base_outdir)
    @info "Planning test case" name

    injection_cfg = cfg["injection"]
    strategy = injection_cfg["strategy"]

    # The cross-section table ships inside TamboSim resources.
    if strategy == "NeutrinoInjection"
        injection_cfg["xs_location"] = joinpath(
            get_tambosim_path(), "resources", "cross_section_tables",
            "cross_sections.h5") * ":CSMS_nutau"
    end

    frames = load_frames(env.geometry)

    # PROPOSAL is initialised once, before injection, for both the tau
    # propagation and the binary-independent Julia side.
    if haskey(cfg, "proposal")
        proposal_cfg = cfg["proposal"]
        proposal_cfg["tablespath"] = ENV["TAMBO_PROPOSAL_TABLES"]
        TamboSim.init_proposal(proposal_cfg)
    end

    inject!(frames, injection_cfg)

    if strategy == "NeutrinoInjection"
        # Keep only events with a final-state lepton, propagate the tau,
        # then keep only events that produced decay products.
        filter!(f -> haskey(f, "injection_final_state"), frames)
        proposal_propagation!(frames, cfg["proposal"])
        filter!(f -> haskey(f, "proposal_decay_products") &&
                     length(f["proposal_decay_products"]) > 0, frames)
    else
        # Drop CR events where the angular sampler missed the detector.
        filter!(f -> haskey(f, "injection_initial_state"), frames)
    end

    # Build the [corsika] config: the binary path and overwrite flag are
    # environment-driven, not part of the committed test config.
    corsika_cfg = cfg["corsika"]
    corsika_cfg["corsika_path"]    = env.shower_bin
    corsika_cfg["force_overwrite"] = true

    # collect_jobs gives the full (job, argv) list so we can cap the count
    # and append a determinism repeat before serialising.
    records = Tuple[]
    corsika_run!(frames, corsika_cfg, base_outdir;
                 executor = collect_jobs(records))

    if haskey(cfg, "max_showers")
        n = min(length(records), cfg["max_showers"])
        records = records[1:n]
    end

    jobs_file = joinpath(base_outdir, "jobs.jsonl")
    open(jobs_file, "w") do io
        for r in records
            JSON3.write(io, (event_id = r.job.event_id,
                             decay_id = r.job.decay_id,
                             outdir   = r.job.outdir,
                             argv     = r.argv))
            println(io)
        end
        # Tier 4a: re-emit the first job into a parallel output directory
        # with identical argv (same seed) so assert.jl can compare them.
        if get(cfg, "determinism_check", false) && !isempty(records)
            r = records[1]
            rep_outdir = joinpath(base_outdir, "_det_repeat",
                                  basename(dirname(r.job.outdir)),
                                  basename(r.job.outdir))
            JSON3.write(io, (event_id = r.job.event_id,
                             decay_id = 99,
                             outdir   = rep_outdir,
                             argv     = _set_f_flag(r.argv, rep_outdir)))
            println(io)
        end
    end

    @info "Planned" name n_showers=length(records) jobs_file
    if isempty(records)
        @warn "No showers planned for $name — injection yielded no jobs. " *
              "For the neutrino case, raise [injection].nevent."
    end
    return length(records)
end

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

function main()
    env = check_prerequisites()
    configs = sort(filter(f -> endswith(f, ".toml"), readdir(CONFIG_DIR; join=true)))
    isempty(configs) && error("No .toml configs found in $CONFIG_DIR")

    total = 0
    for c in configs
        total += plan_one(c, env)
    end
    @info "Phase 1 complete" n_configs=length(configs) total_showers=total
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
