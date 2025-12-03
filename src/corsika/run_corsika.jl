function corsika_run(
    # The next four can be an `Particle`
    pdg::Int64,
    energy::Quantity{T,edim},
    inject_pos::Coordinate{T},
    intercept_pos::Coordinate{T},
    plane::Plane{T},
    thinning::Float64, 
    ecuts::SVector{4, Quantity{T, edim}},
    corsika_path::String,
    corsika_FLUPRO::String,
    corsika_FLUFOR::String,
    outdir::String,
    seed::Int64; 
    parallelize_corsika=parallelize_corsika
) where {T<:Real}
    
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

    if parallelize_corsika 
        corsika_parallel_exec = "\
            $corsika_path \
            --pdg $pdg \
            --energy $(ustrip(energy |> u"GeV")) \
            --xpos $(ustrip(inject_pos.point.x |> u"km")) \
            --ypos $(ustrip(inject_pos.point.y |> u"km")) \
            --zpos $(ustrip(inject_pos.point.z |> u"km")) \
            -f $outdir \
            --xdir $(plane.normal.point.x)) \
            --ydir $(plane.normal.point.y)) \
            --zdir $(plane.normal.point.z)) \
            --x-intercept $(ustrip(intercept_pos.point[1] |> u"km")) \
            --y-intercept $(ustrip(intercept_pos.point[2] |> u"km")) \
            --z-intercept $(ustrip(intercept_pos.point[3] |> u"km")) \
            --emcut $emcut \
            --photoncut $photoncut \
            --mucut $mucut \
            --hadcut $hadcut \
            --emthin $thinning"
        run(`sbatch --time=$time $corsika_sbatch_path $corsika_parallel_exec`)
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
    ecuts::SVector{4, Quantity{T, edim}},
    corsika_path::String,
    corsika_FLUPRO::String,
    corsika_FLUFOR::String,
    outdir::String,
    seed::Int64; 
    parallelize_corsika=parallelize_corsika
) where {T<:Real}

    ray = Ray(particle)
    intersect_coord, t = find_intersection(ray, plane)

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
        parallelize_corsika=parallelize_corsika
    )
end

function corsika_run(
    result::ProposalResult{T},
    plane::Plane{T}, 
    thinning::Float64, 
    ecuts::SVector{4, Quantity{T, edim}},
    corsika_path::String,
    corsika_FLUPRO::String,
    corsika_FLUFOR::String,
    base_outdir::String,
    seed::Int64; 
    parallelize_corsika=parallelize_corsika
) where {T<:Real}
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
            corsika_pathd,
            corsika_FLUPRO,
            corsika_FLUFOR,
            "$(outdir)/shower_$(idx)",
            seed; 
            parallelize_corsika=parallelize_corsika
        )
        idx += 1
    end
    
end
