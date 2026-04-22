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
