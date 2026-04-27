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
        frames::Vector{Frame},
        config::Dict,
        base_outdir;
        prefix::String="corsika",
        inkey::String="proposal_decay_products",
        parallelize=false,
        store_paths=true
    )

Runs CORSIKA for the decay products of events in `frames`. Stores `config` in
the existing C frame under `prefix`, then operates on all Q frames that contain
`inkey`.
"""
function corsika_run(
    frames::Vector{Frame},
    config::Dict,
    base_outdir;
    prefix::String="corsika",
    inkey::String="proposal_decay_products",
    parallelize=false,
    store_paths=true
)
    _ensure_earth_loaded!(frames)
    mframe = get_frame(frames, 'M')
    gframe = get_frame(frames, 'G')

    mframe[prefix] = config

    topography      = gframe["topography"]
    dframe          = get_frame(frames, 'D')
    detector_region = dframe["detector_region"]

    obs_mesh_path     = config["obs_mesh_path"]
    terrain_mesh_path = get(config, "terrain_mesh_path", "")
    hadron_model      = get(config, "hadron_model", "SIBYLL-2.3d")
    thinning          = get(config, "thinning", 1e-6)

    if !haskey(config, "pinecone")
        @warn "Deciding seed via RNG and adding to configuration"
        config["pinecone"] = rand(UInt32)
    end
    Random.seed!(config["pinecone"])

    sbatch_command = parallelize ? config["sbatch_command"] : ""
    ecuts = SVector{3, Float64}([config["em_ecut"], config["mu_ecut"], config["hadron_ecut"]]) * u"GeV"

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
end
