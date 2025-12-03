#function corsika_parallel(
#    proposal_events::Vector{ProposalResult},
#    geo::Geometry,
#    config::Dict{String, Any},
#    indices::Vector{Tuple{Int, Int}}
#)
#
#    if length(indices) > 10000
#        println("Slow down there partner...")
#        println("FASRC forbids more than 10k concurrent jobs!!")
#    end 
#    for i in indices
#        proposal_idx = i[1]
#        decay_idx = i[2]
#        
#        corsika_run(
#            proposal_events[proposal_idx].decay_products[decay_idx],
#            config,
#            geo,
#            proposal_idx,
#            decay_idx; 
#            parallelize_corsika=true
#        )
#        
#    end 
#end 

#function corsika_run(
#    cs::CoordinateSystem{T},
#    # The next four can be an `Particle`
#    pdg::Int64,
#    energy::Quantity{T,edim},
#    direction::Direction{T},
#    inject_pos::Coordinate{T},
#    # Can be gotten from `Plane` + `Particle`
#    intercept_pos::Coordinate{T},
#    #I think these can be a `Plane`
#    plane::Plane{T},
#    obs_z::Quantity{T, ldim}, # Zero point of the coordinate system
#    thinning::Float64, 
#    ecuts::SVector{4, Quantity{T, edim}},
#    corsika_path::String,
#    corsika_FLUPRO::String,
#    corsika_FLUFOR::String,
#    outdir::String,
#    proposal_index::Int64,
#    decay_index::Int64,
#    seed::Int64; 
#    parallelize_corsika=parallelize_corsika
#) where {T<:Real}
#    
#    #convert to CORSIKA internal units of GeV
#    emcut, photoncut, mucut, hadcut = ustrip.(ecuts .|> u"GeV")
#
#    total_index = string(proposal_index) *"_"* string(decay_index)
#
#    plane = convert(cs, plane)
#    inject_pos = convert(cs, inject_pos)
#    intercept_pos = convert(cs, intercept_pos)
#    zenith, azimuth = rad2deg.(cart_to_sph(convert(cs, direction)))
#    azimuth = mod(azimuth, 360)
#    
#
#    # Set environment variables using Julia's ENV dictionary
#    ENV["FLUPRO"] = corsika_FLUPRO
#    ENV["FLUFOR"] = corsika_FLUFOR
#    @show inject_pos.point.x
#    @show inject_pos.point.y
#    @show inject_pos.point.z
#    @show plane.point.point.x
#    @show plane.point.point.y
#    @show plane.point.point.z
#
#    if parallelize_corsika 
#        corsika_parallel_exec = "\
#            $corsika_path \
#            --pdg $pdg \
#            --energy $(ustrip(energy |> u"GeV")) \
#            --zenith $zenith \
#            --azimuth $azimuth \
#            --xpos $(ustrip(inject_pos.point.x |> u"km")) \
#            --ypos $(ustrip(inject_pos.point.y |> u"km")) \
#            --zpos $(ustrip(inject_pos.point.z |> u"km")) \
#            -f $outdir/shower_$total_index \
#            --xdir $(plane.normal.point.x)) \
#            --ydir $(plane.normal.point.y)) \
#            --zdir $(plane.normal.point.z)) \
#            --observation-height $(ustrip(obs_z |> u"km"))\
#            --x-intercept $(ustrip(intercept_pos.point[1] |> u"km")) \
#            --y-intercept $(ustrip(intercept_pos.point[2] |> u"km")) \
#            --z-intercept $(ustrip(intercept_pos.point[3] |> u"km")) \
#            --emcut $emcut \
#            --photoncut $photoncut \
#            --mucut $mucut \
#            --hadcut $hadcut \
#            --emthin $thinning"
#        run(`sbatch --time=$time $corsika_sbatch_path $corsika_parallel_exec`)
#    else 
#        corsika_exec = "$corsika_path \
#            --pdg $pdg \
#            --energy $(ustrip(energy |> u"GeV")) \
#            --zenith $zenith \
#            --azimuth $azimuth \
#            --xpos $(ustrip(inject_pos.point.x |> u"km")) \
#            --ypos $(ustrip(inject_pos.point.y |> u"km")) \
#            --zpos $(ustrip(inject_pos.point.z |> u"km")) \
#            -f $outdir/shower_$total_index \
#            --xdir $(plane.normal.point.x) \
#            --ydir $(plane.normal.point.y) \
#            --zdir $(plane.normal.point.z) \
#            --observation-height $(ustrip(obs_z |> u"km")) \
#            --x-intercept $(ustrip(intercept_pos.point[1] |> u"km")) \
#            --y-intercept $(ustrip(intercept_pos.point[2] |> u"km")) \
#            --z-intercept $(ustrip(intercept_pos.point[3] |> u"km")) \
#            --emcut $emcut \
#            --photoncut $photoncut \
#            --mucut $mucut \
#            --hadcut $hadcut \
#            --emthin $thinning"
#
#        if isdir("$outdir/shower_$total_index")
#            rm("$outdir/shower_$total_index", recursive=true) # CORSIKA doesn't like overwriting files, so we'll do it for them
#        end
#        run(`bash -c $corsika_exec`)
#    end 
#end 

function read_corsika(
    basedir::String,
    cs::CoordinateSystem{T},
    filter_fxn::Union{Function, Nothing}
) where {T<:Real}
    config = open("$(basedir)/particles/config.yaml") do file
        YAML.load(file)
    end
    rot = RotMatrix(SMatrix{3, 3, T, 9}([
        config["x-axis"]...;
        config["y-axis"]...;
        config["plane"]["normal"]
    ]))
    dset = Parquet2.Dataset("$(basedir)/particles/particles.yaml")
    for row in rows

    end

end

#function corsika_run(
#    decay_event::Particle,
#    config::Dict{String, Any},
#
#    geo::Geometry,
#    proposal_idx::Int64,
#    decay_idx::Int64,
#    seed::Int64;
#    parallelize_corsika=parallelize_corsika
#)
#    
#    #plane_orientation = geo.tambo_normal
#    tambo_origin = geo.tambo_coordinates
#    #plane = Plane(plane_orientation, tambo_origin, geo)
#    thinning = config["thinning"]
#    ecuts = SVector{4}([
#        config["em_ecut"] * units.GeV,
#        config["photon_ecut"] * units.GeV,
#        config["mu_ecut"] * units.GeV,
#        config["hadron_ecut"] * units.GeV
#    ])
#    outdir = config["shower_dir"]
#    corsika_path = config["corsika_path"]
#    corsika_FLUPRO = config["FLUPRO"]
#    corsika_FLUFOR = config["FLUFOR"]
#    return corsika_run(
#        decay_event::Particle,
#        #geo.plane,
#        geo,
#        thinning,
#        ecuts,
#        corsika_path,
#        corsika_FLUPRO,
#        corsika_FLUFOR,
#        outdir,
#        proposal_idx::Int64,
#        decay_idx::Int64,
#        seed::Int64;
#        parallelize_corsika=parallelize_corsika
#    )
#end
#
#function corsika_run(
#    decay_event::Particle,
#    #plane::Plane, 
#    geo::Geometry,
#    thinning::Float64,
#    ecuts,
#    corsika_path::String,
#    corsika_FLUPRO::String,
#    corsika_FLUFOR::String,
#    outdir::String,
#    proposal_idx::Int64,
#    decay_idx::Int64,
#    seed::Int64; 
#    parallelize_corsika=parallelize_corsika
#)
#  
#    pdg = decay_event.pdg_mc
#    energy = decay_event.energy/units.GeV
#    zenith = decay_event.direction.θ
#    azimuth = decay_event.direction.ϕ
#    obs_z = geo.tambo_offset.z/ units.km
#
#    distance, point, dot = intersect(decay_event.position, decay_event.direction, geo.plane)
#    distance = distance/units.km
#    intercept_pos = point/units.km 
#    inject_pos = decay_event.position/units.km 
#  
#    return corsika_run(
#        pdg,
#        energy,
#        zenith,
#        azimuth,
#        inject_pos,
#        intercept_pos,
#        geo.plane.n̂.proj,
#        obs_z, 
#        thinning,
#        ecuts,
#        corsika_path,
#        corsika_FLUPRO,
#        corsika_FLUFOR,
#        outdir,
#        proposal_idx,
#        decay_idx,
#        seed;
#        parallelize_corsika=parallelize_corsika
#    )
#end 
#
#struct CorsikaEvent
#  pdg::Int
#  kinetic_energy::Number
#  pos::SVector{3}
#  time::Float64
#  weight::Float64
#end
#
#function CorsikaEvent(a::PyObject, particle_idx::Int)
#  pdg = a["pdg"].to_numpy()[particle_idx]
#  t = a["time"].to_numpy()[particle_idx]
#  x = a["x"].to_numpy()[particle_idx]
#  y = a["y"].to_numpy()[particle_idx]
#  z = a["z"].to_numpy()[particle_idx]
#  kinetic_energy = a["kinetic_energy"].to_numpy()[particle_idx]
#  weight = a["weight"].to_numpy()[particle_idx]
#  return CorsikaEvent(pdg, kinetic_energy, SVector{3}([x, y, z]), t, weight)
#end
#
#function CorsikaEvent(weight)
#    return CorsikaEvent(0, 0.0, 0.0, 0.0, 0.0, 0.0, weight)
#end
##
## This is not really true... Fix this to include events and not just indices
#struct Hit
#  mod::DetectionModule
#  event::CorsikaEvent
#end
#
#function check_inside_mtn(event, geo; verbose=false)
#    decay_pos = event.propped_state.position
#    if inside(decay_pos, geo) 
#        if verbose
#            println("inside mountain")
#        end
#        return false 
#    end 
#    return true 
#end
#
#function check_right_direction(event, geo; verbose=false)
#    """
#    The particle has to travel backwards to reach the plane. 
#    We don't want particles that have to travel backwards to reach the plane. 
#    """
#    decay_pos = event.propped_state.position
#    propped_dir = event.propped_state.direction
#    distance, _, _ = intersect(decay_pos, propped_dir, geo.plane) 
#    if distance/units.m < 0
#        if verbose
#            println("negative distance")
#        end
#        return false 
#    end
#    return true 
#end
#
#function check_plane_dot(event, geo; verbose=false)
#    """
#    The particle direction is in the same direction as the plane's normal vector. 
#    To intercept with positive distance, the particle would have to be traveling from inside the mountain.  
#    """
#
#    decay_pos = event.propped_state.position
#    propped_dir = event.propped_state.direction
#    _, _, dot = intersect(decay_pos, propped_dir, geo.plane)
#    if dot > 0 
#        if verbose
#            println("DOT > 0")
#        end
#        return false 
#    end 
#    return true 
#end
#
#function check_near_orthogonal(event, geo; verbose=false)
#    """
#    Cutting near-orthogonal particle directions with the plane normal. 
#    """
#    decay_pos = event.propped_state.position
#    propped_dir = event.propped_state.direction
#    #plane = Tambo.Plane(minesite_normal_vec, minesite_coord, geo)      
#    _, _, dot = intersect(decay_pos, propped_dir, geo.plane) 
#    if abs(dot) < 1e-3
#        if verbose
#            println("ORTHOGONAL")
#        end
#        return false  
#    end
#    return true 
#end
#
#function check_z_intercept(event, geo; verbose=false)
#    """
#    point[3] = z-intercept of particle and TAMBO plane. If the elevation in TAMBO coords is greater than 10km, cut. 
#    """
#    decay_pos = event.propped_state.position
#    propped_dir = event.propped_state.direction
#    #plane = Tambo.Plane(minesite_normal_vec, minesite_coord, geo)      
#    _, point, _ = intersect(decay_pos, propped_dir, geo.plane) 
#    if point.z > 10 * units.km
#        if verbose
#            println("Z-intercept GREATER THAN 10km")
#        end
#        return false 
#    end 
#    return true 
#end
#
#function check_track_length(event, geo; verbose=false, max_distance=20units.km)
#    """
#    If the distance length is greater than 20km between particle position and intercept with TAMBO plane, cut. 
#    """
#    decay_pos = event.propped_state.position
#    propped_dir = event.propped_state.direction
#    #plane = Tambo.Plane(minesite_normal_vec, minesite_coord, geo)      
#    distance, _, _ = intersect(decay_pos, propped_dir, geo.plane)
#    if distance > max_distance
#        if verbose
#            println("Distance length greater than 20km") 
#        end
#        return false 
#    end 
#    return true 
#end
#
#function check_intersections(event, geo; verbose=false)
#    decay_pos = event.propped_state.position
#    propped_dir = event.propped_state.direction
#    _, point, _ = intersect(decay_pos, propped_dir, geo.plane)
#    t = Track(decay_pos, point)
#    intersections = intersect(t, geo)
#
#    """
#    If the intersection with the mountain > 1 then we cut.
#    When it intersects TAMBO plane.
#    """
#    if length(intersections) > 1
#        return false
#    end
#    
#    return true 
#end
#
#function check_passed_through_rock(event::ProposalResult, geo; verbose=false, thresh=4units.km)
#    track = Tambo.Track(
#        event.continuous_losses.position,
#        reverse(event.propped_state.direction),
#        geo.box
#    )
#    segments = Tambo.computesegments(track, geo)
#    
#    ℓ_inrock = 0
#    for segment in segments
#        if segment.medium_name=="Air"
#            continue
#        end
#        ℓ_inrock += segment.length
#    end
#    return ℓ_inrock >= thresh
#end
#
#function check_neutrino(daughter_particle::Particle; verbose = false)
#    pdg = daughter_particle.pdg_mc
#    if abs(pdg) == 16 || abs(pdg) == 14 || abs(pdg) == 12 
#        if verbose 
#            println("daughter particle is a neutrino")
#        end 
#        return true
#    else 
#        if verbose 
#            println("daughter is not a neutrino")
#        end
#        return false 
#    end 
#end
#
#function should_do_corsika(
#    event::ProposalResult,
#    geo::Geometry,
#    criteria::Array{Function};
#    verbose=false,
#    check_mode=false
#)
#    # Seems like we should do `check_mode` via dependency injection but weeeeeeeeeeee
#    if check_mode
#        b = Bool[]
#    end
#
#    for criterion in criteria
#        v = criterion(event, geo; verbose=verbose)
#        if check_mode
#            push!(b, v)
#        else
#            if !v
#                return false
#            end
#        end
#    end
#
#    if check_mode
#        return b
#    else
#        return true
#    end
#end
#
#function should_do_corsika(
#    event::ProposalResult,
#    geo::Geometry;
#    verbose=false,
#    check_mode=false
#)
#    checks = [
#        check_inside_mtn,
#        check_right_direction,
#        check_plane_dot,
#        check_near_orthogonal,
#        check_z_intercept,
#        check_track_length,
#        check_intersections,
#        #check_passed_through_rock,
#    ]
#    return should_do_corsika(event, geo, checks; verbose=verbose, check_mode=check_mode)
#end
