"""
    corsika_run(
        pdg::Int64,
        energy::Quantity{T,edim},
        inject_pos::Coordinate{T},
        intercept_pos::Coordinate{T},
        plane::Plane{T},
        thinning::Float64, 
        ecuts,
        corsika_path::String,
        corsika_FLUPRO::String,
        corsika_FLUFOR::String,
        outdir::String,
        seed::Int64; 
        sbatch_command=""
    ) where {T}

Executes a CORSIKA simulation for a single primary particle.

This function constructs and runs a command for the CORSIKA executable. It sets up the
primary particle's properties (PDG ID, energy, position, direction), observation plane,
energy cuts, and other simulation parameters. It can run CORSIKA directly or submit it
as a job via a sbatch command.

# Arguments
- `pdg::Int64`: The PDG ID of the primary particle.
- `energy`: The energy of the primary particle.
- `inject_pos`: The injection position of the particle.
- `intercept_pos`: The position where the particle intercepts the observation plane.
- `plane::Plane{T}`: The observation plane.
- `thinning::Float64`: The thinning level for the simulation.
- `ecuts`: A collection of energy cuts for different particle types (EM, photon, muon, hadron).
- `corsika_path::String`: The path to the CORSIKA executable.
- `corsika_FLUPRO::String`: The value for the `FLUPRO` environment variable.
- `corsika_FLUFOR::String`: The value for the `FLUFOR` environment variable.
- `outdir::String`: The directory where the output files will be saved.
- `seed::Int64`: The random seed for the simulation.
- `sbatch_command`: An optional sbatch command to run CORSIKA in parallel.
"""
function corsika_run(
    pdg::Int64,
    energy::Quantity{T,edim},
    inject_pos::Coordinate{T},
    intercept_pos::Coordinate{T},
    plane::Plane{T},
    thinning::Float64, 
    ecuts,
    corsika_path::String,
    corsika_FLUPRO::String,
    corsika_FLUFOR::String,
    outdir::String,
    seed::Int64; 
    sbatch_command=""
) where {T}
    
    cs = inject_pos.coordinate_system
    rot = AngleAxis(-π/2, cs.origin...)
    cs = CoordinateSystem(cs.origin, Float64.(cs.rotation*rot))
    #convert to CORSIKA internal units of GeV
    emcut, photoncut, mucut, hadcut = ustrip.(ecuts .|> u"GeV")

    plane = convert(cs, plane)
    inject_pos = convert(cs, inject_pos)
    intercept_pos = convert(cs, intercept_pos)

    ## Set environment variables using Julia's ENV dictionary
    ENV["FLUPRO"] = corsika_FLUPRO
    ENV["FLUFOR"] = corsika_FLUFOR

    if length(sbatch_command) > 0
        corsika_parallel_exec = "\
            $corsika_path \
            --pdg $pdg \
            --energy $(ustrip(energy |> u"GeV")) \
            --xpos $(ustrip(inject_pos.point.x |> u"km")) \
            --ypos $(ustrip(inject_pos.point.y |> u"km")) \
            --zpos $(ustrip(inject_pos.point.z |> u"km")) \
            -f $outdir \
            --xdir $(plane.normal.point.x) \
            --ydir $(plane.normal.point.y) \
            --zdir $(plane.normal.point.z) \
            --x-intercept $(ustrip(intercept_pos.point[1] |> u"km")) \
            --y-intercept $(ustrip(intercept_pos.point[2] |> u"km")) \
            --z-intercept $(ustrip(intercept_pos.point[3] |> u"km")) \
            --emcut $emcut \
            --photoncut $photoncut \
            --mucut $mucut \
            --hadcut $hadcut \
            --emthin $thinning"
        run(`sbatch $sbatch_command $corsika_parallel_exec`)
    else 
        corsika_exec = "$corsika_path \
            --pdg $pdg \
            --energy $(ustrip(energy |> u"GeV")) \
            --xpos $(ustrip(inject_pos.point.x |> u"km")) \
            --ypos $(ustrip(inject_pos.point.y |> u"km")) \
            --zpos $(ustrip(inject_pos.point.z |> u"km")) \
            -f $outdir \
            --xdir $(plane.normal.point.x) \
            --ydir $(plane.normal.point.y) \
            --zdir $(plane.normal.point.z) \
            --x-intercept $(ustrip(intercept_pos.point[1] |> u"km")) \
            --y-intercept $(ustrip(intercept_pos.point[2] |> u"km")) \
            --z-intercept $(ustrip(intercept_pos.point[3] |> u"km")) \
            --emcut $emcut \
            --photoncut $photoncut \
            --mucut $mucut \
            --hadcut $hadcut \
            --emthin $thinning \
            --seed $seed"

        if isdir("$outdir")
            rm("$outdir", recursive=true) # CORSIKA doesn't like overwriting files, so we'll do it for them
        end
        run(`bash -c $corsika_exec`)
    end 
end 

"""
    corsika_run(
        particle::Particle{T},
        plane::Plane{T},
        thinning::Float64, 
        ecuts,
        corsika_path::String,
        corsika_FLUPRO::String,
        corsika_FLUFOR::String,
        outdir::String,
        seed::Int64; 
        sbatch_command=""
    ) where {T}

A convenience wrapper for `corsika_run` that takes a `Particle` object.

This function calculates the intersection point of the particle's trajectory with the
observation plane and then calls the main `corsika_run` function with the detailed parameters.

# Arguments
- `particle::Particle{T}`: The primary particle for the simulation.
- `plane::Plane{T}`: The observation plane.
- `thinning::Float64`: The thinning level.
- `ecuts`: Energy cuts for different particle types.
- `corsika_path::String`: Path to the CORSIKA executable.
- `corsika_FLUPRO::String`: Value for the `FLUPRO` environment variable.
- `corsika_FLUFOR::String`: Value for the `FLUFOR` environment variable.
- `outdir::String`: The output directory.
- `seed::Int64`: The random seed.
- `sbatch_command`: Optional sbatch command for parallel execution.
"""
function corsika_run(
    particle::Particle{T},
    plane::Plane{T},
    thinning::Float64,
    ecuts,
    corsika_path::String,
    corsika_FLUPRO::String,
    corsika_FLUFOR::String,
    outdir::String,
    seed::Int64;
    sbatch_command=""
) where {T}

    ray = Ray(particle)
    intersect_coord, t = find_intersection(ray, plane)
    # Particle is past point
    if isnothing(intersect_coord)
        @show outdir
        return
    end

    corsika_run(
        Int(particle.pdg),
        particle.energy,
        particle.position,
        intersect_coord,
        plane,
        thinning,
        ecuts,
        corsika_path,
        corsika_FLUPRO,
        corsika_FLUFOR,
        outdir,
        seed;
        sbatch_command=sbatch_command
    )
end

"""
    corsika_run(
        particle::Particle{T},
        earth::Earth,
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

Finds the intersection of the particle trajectory with the detector region of
`earth`, then calls `tambo_shower` with `--inject-x/y/z` (particle position)
and `--intercept-x/y/z` (intercept on detector region), both in ECEF metres.

# Arguments
- `particle::Particle{T}`: Primary particle; `position` is the injection point.
- `earth::Earth`: Detector geometry; `earth.detector_region` selects detection triangles.
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
    earth::Earth,
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
    detector_triangles = earth.topography[earth.detector_region]
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
