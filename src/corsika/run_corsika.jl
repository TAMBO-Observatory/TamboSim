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
