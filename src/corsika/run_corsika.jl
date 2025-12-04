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
        particle.pdg_id,
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

function corsika_run(
    result::ProposalResult{T},
    plane::Plane{T},
    thinning::T, 
    ecuts,
    corsika_path::String,
    corsika_FLUPRO::String,
    corsika_FLUFOR::String,
    base_outdir::String,
    seed::Int64; 
    sbatch_command::String=""
) where {T}
    idx = 1
    for particle in result.decay_products
        if abs(particle.pdg_id) in [12,14,16]
            continue
        end
        corsika_run(
            particle,
            plane,
            thinning, 
            ecuts,
            corsika_path,
            corsika_FLUPRO,
            corsika_FLUFOR,
            "$(base_outdir)/shower_$(idx)",
            seed; 
            sbatch_command=sbatch_command
        )
        idx += 1
    end
    
end
