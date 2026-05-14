"""
    corsika_run(
        particle::Particle{T},
        topography,
        detector_region,
        obs_mesh_path::String,
        terrain_mesh_path::String,
        ecuts,
        corsika_path::String,
        outdir::String,
        seed::Int64;
        thinning::Float64=1e-6,
        nevent::Int=1,
        hadron_model::String="SIBYLL-2.3d",
        sbatch_command=""
    ) where {T}

Run `tambo_shower` (CORSIKA 8 mesh-based) for a primary particle.

Finds the intersection of the particle trajectory with the detector region, then calls
`tambo_shower` with `--inject-x/y/z` and `--intercept-x/y/z`, both in ECEF metres.

# Arguments
- `particle::Particle{T}`: Primary particle; `position` is the injection point.
- `topography`: Full topography mesh (vector of triangles).
- `detector_region`: Indices of detector-region triangles within `topography`.
- `obs_mesh_path::String`: Path to the observation-region PLY file (ECEF metres).
- `terrain_mesh_path::String`: Path to the terrain PLY file, or `""` to disable.
- `ecuts`: Three energy cuts `(emcut, mucut, hadcut)` as `Quantity` values.
- `corsika_path::String`: Path to the `tambo_shower` executable.
- `outdir::String`: Output directory (removed and recreated if it already exists).
- `seed::Int64`: Random seed (0 = auto).
- `thinning::Float64`: EM thinning fraction (passed as `--emthin`). Default `1e-6`.
- `nevent::Int`: Number of showers to simulate. Default 1.
- `hadron_model::String`: High-energy hadronic model name. Default `"SIBYLL-2.3d"`.
- `sbatch_command`: Optional sbatch prefix for cluster submission.
"""
function corsika_run(
    particle::Particle{T},
    topography,
    detector_region,
    obs_mesh_path::String,
    terrain_mesh_path::String,
    ecuts,
    corsika_path::String,
    outdir::String,
    seed::Int64;
    thinning::Float64=1e-6,
    nevent::Int=1,
    hadron_model::String="SIBYLL-2.3d",
    sbatch_command=""
) where {T}

    # Build a BVH from detector-region triangles only
    detector_triangles = topography[detector_region]
    detector_bvh = BVHTree(detector_triangles)

    # Find where the particle trajectory intersects the detector region
    ray = Ray(particle)
    isect = find_intersect(ray, detector_bvh)
    if isnothing(isect)
        @warn "corsika_run (mesh): no intersection with detector region; skipping $outdir"
        return
    end

    # Convert injection position and intercept to ECEF metres
    inject_ecef    = convert(ecefcoordinates, particle.position)
    intercept_ecef = convert(ecefcoordinates, isect.point)
    injectX    = ustrip(u"m", inject_ecef.point[1])
    injectY    = ustrip(u"m", inject_ecef.point[2])
    injectZ    = ustrip(u"m", inject_ecef.point[3])
    interceptX = ustrip(u"m", intercept_ecef.point[1])
    interceptY = ustrip(u"m", intercept_ecef.point[2])
    interceptZ = ustrip(u"m", intercept_ecef.point[3])

    emcut, mucut, hadcut = ustrip.(collect(ecuts) .|> u"GeV")
    taucut = mucut  # no separate tau cut in config; default to muon cut

    if isdir(outdir)
        rm(outdir, recursive=true)
    end

    cmd_parts = [
        corsika_path,
        "--pdg",         string(Int(particle.pdg)),
        "--energy",      string(ustrip(particle.energy |> u"GeV")),
        "--inject-x",    string(injectX),
        "--inject-y",    string(injectY),
        "--inject-z",    string(injectZ),
        "--intercept-x", string(interceptX),
        "--intercept-y", string(interceptY),
        "--intercept-z", string(interceptZ),
        "--obs-mesh",    obs_mesh_path,
        "--emcut",       string(emcut),
        "--hadcut",      string(hadcut),
        "--mucut",       string(mucut),
        "--taucut",      string(taucut),
        "-M",            hadron_model,
        "-N",            string(nevent),
        "--seed",        string(seed),
        "--emthin",      string(thinning),
        "-f",            outdir,
    ]
    if !isempty(terrain_mesh_path)
        append!(cmd_parts, ["--terrain-mesh", terrain_mesh_path])
    end

    if isempty(sbatch_command)
        run(Cmd(cmd_parts))
    else
        run(`sbatch $sbatch_command $(join(cmd_parts, " "))`)
    end
end

"""
    corsika_run(
        frames::TamboFrames,
        config::Dict,
        base_outdir;
        prefix::String="corsika",
        inkey::String="proposal_decay_products",
        parallelize=false,
        store_paths=true
    )

Run CORSIKA 8 (`tambo_shower`) on the decay products from PROPOSAL,
producing one output directory per (event, decay-product) pair under
`base_outdir`. Mutates `frames` by snapshotting `config` onto the
existing M frame under `prefix`. For each Q frame containing `inkey`,
loops over its `<inkey>` particles (skipping neutrinos by PDG) and
dispatches the per-particle method below.

Mesh files (`obs_surface.ply` and, if `use_terrain_mesh` is true,
`terrain.ply`) are derived from the G/D frames and written to
`base_outdir` before the shower loop. When `parallelize=false` they are
removed after the loop completes. When `parallelize=true` they are left
in place because the submitted cluster jobs have not yet run; the caller
is responsible for cleaning up `base_outdir` once all jobs finish.

# Arguments
- `frames::TamboFrames`: must already have an M frame and at least one
  Q frame with `inkey` populated (typically run after
  `proposal_propagation!`).
- `config::Dict`: parsed `[corsika]` TOML table. Consults
  `"corsika_path"`, `"em_ecut"`, `"mu_ecut"`, `"hadron_ecut"`,
  `"hadron_model"` (optional, default `"SIBYLL-2.3d"`),
  `"thinning"` (optional, default `1e-6`),
  `"use_terrain_mesh"` (optional, default `true`),
  `"seed"` (RNG seed), and `"sbatch_command"` (only when
  `parallelize=true`).
- `base_outdir`: directory under which per-event output dirs
  (`event_<id>/shower_<idx>/`) are created.

# Keyword arguments
- `prefix::String`: namespace for the config snapshot. Default `"corsika"`.
- `inkey::String`: Q-frame key carrying the particles to shower.
  Default `"proposal_decay_products"`.
- `parallelize::Bool`: if `true`, prefix the binary invocation with
  `config["sbatch_command"]` for cluster submission.
- `store_paths::Bool`: if `true`, write a `"corsika_directories"` key on
  each Q frame listing every shower output dir dispatched for that event.
"""
function corsika_run(
    frames::TamboFrames,
    config::Dict,
    base_outdir;
    prefix::String="corsika",
    inkey::String="proposal_decay_products",
    parallelize=false,
    store_paths=true
)
    m_frame = _get_last_frame(frames, 'M')
    g_frame = m_frame.g_frame
    d_frame = m_frame.d_frame

    m_frame[prefix] = config

    topography      = g_frame["topography"]
    detector_region = d_frame["detector_region"]

    use_terrain_mesh = get(config, "use_terrain_mesh", true)
    hadron_model     = get(config, "hadron_model", "SIBYLL-2.3d")
    thinning         = get(config, "thinning", 1e-6)

    if !haskey(config, "seed")
        @warn "Deciding seed via RNG and adding to configuration"
        config["seed"] = rand(UInt32)
    end
    Random.seed!(config["seed"])

    sbatch_command = parallelize ? config["sbatch_command"] : ""
    ecuts = SVector{3, Float64}([config["em_ecut"], config["mu_ecut"], config["hadron_ecut"]]) * u"GeV"

    mkpath(base_outdir)
    obs_mesh_path     = joinpath(base_outdir, "obs_surface.ply")
    terrain_mesh_path = use_terrain_mesh ? joinpath(base_outdir, "terrain.ply") : ""
    dump_to_ply(d_frame, obs_mesh_path)
    use_terrain_mesh && dump_to_ply(g_frame, terrain_mesh_path; watertight_depth=10_000.0)

    try
        for frame in filter(f -> f.stream == 'Q', frames)
            haskey(frame, inkey) || continue
            paths = String[]
            decay_products = frame[inkey]
            for (idx, particle) in enumerate(decay_products)
                abs(Int(particle.pdg)) in [12, 14, 16] && continue
                output_dir = "$(base_outdir)/event_$(lpad(frame["event_id"], 6, '0'))/shower_$(idx)/"
                push!(paths, output_dir)
                isdir(output_dir) && continue
                seed = Int(rand(UInt32))
                try
                    corsika_run(
                        particle,
                        topography,
                        detector_region,
                        obs_mesh_path,
                        terrain_mesh_path,
                        ecuts,
                        config["corsika_path"],
                        output_dir,
                        seed;
                        thinning=thinning,
                        hadron_model=hadron_model,
                        sbatch_command=sbatch_command
                    )
                catch e
                    @warn "CORSIKA failed for event $(frame["event_id"]) shower $(idx)" exception=e
                end
            end
            store_paths && (frame["corsika_directories"] = paths)
        end
    finally
        if !parallelize
            rm(obs_mesh_path; force=true)
            use_terrain_mesh && rm(terrain_mesh_path; force=true)
        end
    end
end
