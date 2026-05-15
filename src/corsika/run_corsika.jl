
"""
    _make_job(particle, event_id, decay_id, base_seed, detector_bvh, base_outdir)

Build a single CORSIKA job record. Returns `nothing` if `particle`'s
trajectory does not intersect `detector_bvh`. Internal helper for
[`plan_corsika_jobs`](@ref).
"""
function _make_job(particle, event_id, decay_id, base_seed, detector_bvh, base_outdir)
    ray = Ray(particle)
    isect = find_intersect(ray, detector_bvh)
    isnothing(isect) && return nothing
    seed = Int(abs(hash((base_seed, event_id, decay_id))) % typemax(Int32))
    outdir = joinpath(base_outdir,
                      "event_$(lpad(event_id, 6, '0'))",
                      "shower_$(decay_id)")
    return (; event_id, decay_id, primary=particle, intercept=isect.point, seed, outdir)
end

"""
    plan_corsika_jobs(frames::TamboFrames, config::Dict, base_outdir::String)
        -> Vector{NamedTuple}

Strategy-dispatched job enumeration for CORSIKA. Returns one NamedTuple
per shower to dispatch, with fields
`(event_id, decay_id, primary, intercept, seed, outdir)`. `outdir` is the
absolute path `<base_outdir>/event_<padded>/shower_<idx>/`.

Branches on the latest M frame's `m["injection"]["strategy"]`:

- `"NeutrinoInjection"`: one job per non-neutrino (`pdg ∉ {12,14,16}`)
  particle in `q["proposal_decay_products"]`.
- `"CosmicRayInjection"`: one job per `q["injection_initial_state"]`
  (the arriving primary), with `decay_id = 1`.

Jobs whose primary trajectory does not intersect the detector region are
dropped. Seeds are derived deterministically from
`hash((config["seed"], event_id, decay_id))`, so re-running
`plan_corsika_jobs` on the same inputs yields identical jobs with identical
seeds.

Reads `detector_bvh` from the D frame attached to the latest M frame.
"""
function plan_corsika_jobs(frames::TamboFrames, config::Dict, base_outdir::String)

    m_frame = _get_last_frame(frames, 'M')
    d_frame = m_frame.d_frame
    detector_bvh = d_frame["detector_bvh"]

    strategy = m_frame["injection"]["strategy"]
    base_seed = config["seed"]

    jobs = NamedTuple[]
    for frame in frames.q_frames
        event_id = frame["event_id"]
        
        if strategy == "NeutrinoInjection"
            haskey(frame, "proposal_decay_products") || continue
            for (idx, particle) in enumerate(frame["proposal_decay_products"])
                abs(Int(particle.pdg)) in (12, 14, 16) && continue
                job = _make_job(particle, event_id, idx, base_seed,
                                detector_bvh, base_outdir)
                isnothing(job) && continue
                push!(jobs, job)
            end

        elseif strategy == "CosmicRayInjection"
            haskey(frame, "injection_initial_state") || continue
            job = _make_job(frame["injection_initial_state"], event_id, 1,
                            base_seed, detector_bvh, base_outdir)
            isnothing(job) && continue
            push!(jobs, job)
            
        else
            error("plan_corsika_jobs: unknown injection strategy $(strategy)")
        end
    end
    return jobs
end

"""
    build_corsika_argv(job, mesh_paths, ecuts, config) -> Vector{String}

Build the argv vector for one invocation of `tambo_shower`. 

# Arguments
- `job::NamedTuple`: one element from [`plan_corsika_jobs`](@ref). Uses
  `job.primary`, `job.intercept`, `job.seed`, `job.outdir`.
- `mesh_paths::NamedTuple`: `(obs, terrain)`; `terrain` may be `""` to
  disable the terrain mesh.
- `ecuts`: 3-tuple `(emcut, mucut, hadcut)` of `Quantity` energies.
- `config::Dict`: `[corsika]` TOML table. Consults `"corsika_path"`,
  `"hadron_model"` (default `"SIBYLL-2.3d"`), `"thinning"` (default
  `1e-6`), `"nevent"` (default `1`), `"force_overwrite"` (default
  `false`; passes `--force` to the binary).
"""
function build_corsika_argv(job::NamedTuple, mesh_paths::NamedTuple, ecuts, config::Dict)
    primary = job.primary
    inject_ecef    = convert(ecefcoordinates, primary.position)
    intercept_ecef = convert(ecefcoordinates, job.intercept)
    injectX    = ustrip(u"m", inject_ecef.point[1])
    injectY    = ustrip(u"m", inject_ecef.point[2])
    injectZ    = ustrip(u"m", inject_ecef.point[3])
    interceptX = ustrip(u"m", intercept_ecef.point[1])
    interceptY = ustrip(u"m", intercept_ecef.point[2])
    interceptZ = ustrip(u"m", intercept_ecef.point[3])

    emcut, mucut, hadcut = ustrip.(collect(ecuts) .|> u"GeV")
    taucut = mucut  # no separate tau cut in config; default to muon cut

    hadron_model    = get(config, "hadron_model", "SIBYLL-2.3d")
    thinning        = get(config, "thinning", 1e-6)
    nevent          = get(config, "nevent", 1)
    force_overwrite = get(config, "force_overwrite", false)

    argv = [
        config["corsika_path"],
        "--pdg",         string(Int(primary.pdg)),
        "--energy",      string(ustrip(primary.energy |> u"GeV")),
        "--inject-x",    string(injectX),
        "--inject-y",    string(injectY),
        "--inject-z",    string(injectZ),
        "--intercept-x", string(interceptX),
        "--intercept-y", string(interceptY),
        "--intercept-z", string(interceptZ),
        "--obs-mesh",    mesh_paths.obs,
        "--emcut",       string(emcut),
        "--hadcut",      string(hadcut),
        "--mucut",       string(mucut),
        "--taucut",      string(taucut),
        "-M",            hadron_model,
        "-N",            string(nevent),
        "--seed",        string(job.seed),
        "--emthin",      string(thinning),
        "-f",            job.outdir,
    ]
    if !isempty(mesh_paths.terrain)
        append!(argv, ["--terrain-mesh", mesh_paths.terrain])
    end
    force_overwrite && push!(argv, "--force")
    return argv
end

# =============================================================================
# Built-in executors
# =============================================================================

"""
    run_local(argv, job)

Default [`corsika_run!`](@ref) executor: ensures `job.outdir` exists
(removing any prior contents) and runs `Cmd(argv)` synchronously.
"""
function run_local(argv, job)
    if isdir(job.outdir)
        rm(job.outdir, recursive=true)
    end
    mkpath(job.outdir)
    run(Cmd(argv))
end

"""
    run_sbatch(prefix::String) -> executor

Return a [`corsika_run!`](@ref) executor that submits each job via
`sbatch <prefix split on whitespace> --wrap="<argv joined by spaces>"`.
`prefix` carries sbatch options as a single whitespace-separated string;
it is split locally because Julia backticks don't shell-split interpolated
strings. The job command is passed through `--wrap` so sbatch executes it
inline rather than treating it as a script path.
"""
function run_sbatch(prefix::String)
    prefix_args = split(prefix)
    return (argv, _job) -> run(`sbatch $prefix_args --wrap=$(join(argv, " "))`)
end

"""
    dump_to_file(io::IO) -> executor

Return a [`corsika_run!`](@ref) executor that writes one JSONL record per
job to `io`. Each line is a JSON object with keys `event_id`, `decay_id`,
`outdir`, and `argv` (the full argv vector). Does not create directories
or run anything; consumable by Snakemake / OSG / `jq` / bash.
"""
function dump_to_file(io::IO)
    return function (argv, job)
        record = (event_id=job.event_id,
                  decay_id=job.decay_id,
                  outdir=job.outdir,
                  argv=argv)
        JSON3.write(io, record)
        write(io, '\n')
    end
end

"""
    collect_jobs(records::Vector) -> executor

Return a [`corsika_run!`](@ref) executor that pushes `(; job, argv)`
NamedTuples into `records` and does nothing else. Intended for the
"collect → filter → dispatch yourself" workflow:

```julia
records = []
corsika_run!(frames, config, base_outdir; executor=collect_jobs(records))
records = filter(r -> r.job.primary.energy > 1u"PeV", records)
for r in records
    run(Cmd(r.argv))   # or sbatch, or anything else
end
```
"""
function collect_jobs(records::Vector)
    return (argv, job) -> push!(records, (; job, argv))
end

"""
    _run_jobs(jobs, mesh_paths, ecuts, config, executor)

Internal dispatch loop. For each job in `jobs`, build the argv vector and
hand `(argv, job)` to `executor`. Failures in `executor` are caught and
logged, not propagated.
"""
function _run_jobs(jobs, mesh_paths, ecuts, config, executor)
    for job in jobs
        argv = build_corsika_argv(job, mesh_paths, ecuts, config)
        try
            executor(argv, job)
        catch e
            @warn "CORSIKA dispatch failed for event $(job.event_id) shower $(job.decay_id)" exception=e
        end
    end
end

"""
    corsika_run!(frames::TamboFrames, config::Dict, base_outdir;
                executor=nothing, prefix="corsika")

Orchestrate CORSIKA 8 (`tambo_shower`) over a `TamboFrames`. Strategy-
dispatched: handles both `NeutrinoInjection` (one shower per non-neutrino
decay product) and `CosmicRayInjection` (one shower per primary).

Steps performed in order:

1. Stamps `config` onto the M frame at `m[prefix]`.
2. Dumps `obs_surface.ply` and (optionally) `terrain.ply` under
   `base_outdir`.
3. Enumerates jobs via [`plan_corsika_jobs`](@ref) — deterministic given
   `config["seed"]`.
4. Stamps each Q frame with `q["corsika_directories"]` listing *all*
   shower outdirs planned for that event. Always done — downstream
   `read_corsika_hits!` depends on it.
5. For each job, builds argv via [`build_corsika_argv`](@ref) and hands
   it to `executor(argv, job)`.
6. Removes the mesh PLYs on exit if `executor === run_local`; leaves
   them in place otherwise (other executors may run later).

# Executor selection

If `executor` is `nothing` (default), it is resolved from
`config["executor"]`. Built-ins: `"run_local"` (default), `"run_sbatch"`
(requires `executor_sbatch_prefix`), `"dump_to_file"` (requires
`executor_dump_path`). A Julia caller may pass a function directly
instead.

# Caller patterns

```julia
# Run locally inline:
corsika_run!(frames, config, base_outdir)

# Cluster submit:
corsika_run!(frames, config, base_outdir;
            executor=run_sbatch(config["executor_sbatch_prefix"]))

# Dump jobs.jsonl for an external scheduler:
open("jobs.jsonl", "w") do io
    corsika_run!(frames, config, base_outdir; executor=dump_to_file(io))
end

# Collect, filter, dispatch yourself:
records = []
corsika_run!(frames, config, base_outdir; executor=collect_jobs(records))
records = filter(r -> r.job.primary.energy > 1u"PeV", records)
for r in records; run(Cmd(r.argv)); end
```

# Intent vs actuality

Q-frame `corsika_directories` always reflects the *full* job list from
`plan_corsika_jobs`, regardless of what the executor actually dispatches.

# Config keys consulted
- `"corsika_path"`, `"em_ecut"`, `"mu_ecut"`, `"hadron_ecut"` — required
- `"seed"` — optional; randomized + stored if missing
- `"hadron_model"`, `"thinning"`, `"nevent"`, `"use_terrain_mesh"`,
  `"force_overwrite"` — optional
- `"executor"`, `"executor_sbatch_prefix"`, `"executor_dump_path"` — optional
"""
function corsika_run!(
    frames::TamboFrames,
    config::Dict,
    base_outdir;
    executor=nothing,
    prefix::String="corsika",
)
    m_frame = _get_last_frame(frames, 'M')
    g_frame = m_frame.g_frame
    d_frame = m_frame.d_frame
    m_frame[prefix] = config

    if !haskey(config, "seed")
        @warn "Deciding seed via RNG and adding to configuration"
        config["seed"] = rand(UInt32)
    end

    use_terrain_mesh = get(config, "use_terrain_mesh", true)
    mkpath(base_outdir)
    obs_mesh_path     = joinpath(base_outdir, "obs_surface.ply")
    terrain_mesh_path = use_terrain_mesh ? joinpath(base_outdir, "terrain.ply") : ""
    dump_to_ply(d_frame, obs_mesh_path)
    use_terrain_mesh && dump_to_ply(g_frame, terrain_mesh_path; watertight_depth=10_000.0)
    mesh_paths = (obs=obs_mesh_path, terrain=terrain_mesh_path)

    jobs = plan_corsika_jobs(frames, config, base_outdir)

    by_event = Dict{Int, Vector{String}}()
    for j in jobs
        push!(get!(by_event, j.event_id, String[]), j.outdir)
    end
    for q in frames.q_frames
        event_id = q["event_id"]
        haskey(by_event, event_id) || continue
        q["corsika_directories"] = by_event[event_id]
    end

    ecuts = SVector{3, Float64}([config["em_ecut"], config["mu_ecut"], config["hadron_ecut"]]) * u"GeV"

    # Decide whether to clean up meshes on exit. Only run_local is guaranteed
    # to have finished its work before this function returns.
    cleanup_meshes = executor === run_local ||
                     (isnothing(executor) && get(config, "executor", "run_local") == "run_local")

    try
        if !isnothing(executor)
            _run_jobs(jobs, mesh_paths, ecuts, config, executor)
        else
            name = get(config, "executor", "run_local")
            if name == "run_local"
                _run_jobs(jobs, mesh_paths, ecuts, config, run_local)

            elseif name == "run_sbatch"
                haskey(config, "executor_sbatch_prefix") ||
                    error("executor=run_sbatch requires executor_sbatch_prefix in [corsika]")
                _run_jobs(jobs, mesh_paths, ecuts, config,
                          run_sbatch(config["executor_sbatch_prefix"]))

            elseif name == "dump_to_file"
                haskey(config, "executor_dump_path") ||
                    error("executor=dump_to_file requires executor_dump_path in [corsika]")
                open(config["executor_dump_path"], "w") do io
                    _run_jobs(jobs, mesh_paths, ecuts, config, dump_to_file(io))
                end

            else
                error("Unknown executor: $name. Built-ins: run_local, run_sbatch, dump_to_file")
            end
        end

    finally
        if cleanup_meshes
            rm(obs_mesh_path; force=true)
            !isempty(terrain_mesh_path) && rm(terrain_mesh_path; force=true)
        end
    end

end
