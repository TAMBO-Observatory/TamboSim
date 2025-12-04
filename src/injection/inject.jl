function inject_event(
    pdg_id::Int,
    earth::Earth,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    xs::CrossSection;
    detector_triangles::Union{Vector{Triangle{T}}, Nothing}=nothing,
    detector_normals::Union{Vector{Direction{T}}, Nothing}=nothing,
    detector_bvh::Union{BVHTree{T}, Nothing}=nothing,
    #detector_areas::Union{Vector{Quantity{T,U^2,typeof(u"m^2")}}, Nothing} = nothing,
    detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing} = nothing,
    epsilon=1e-6*u"m",
    event_id::Int=0
) where {T<:Real}

    cs = CoordinateSystem(earth)
    # Compute parameters is not passed.
    # You generally should not do this as this is fixed per geometry
    # I mostly leave this in for now as a convenience
    if isnothing(detector_triangles)
        detector_triangles = earth.topography[earth.detector_region]
    end
    if isnothing(detector_normals)
        println("Computing normals. This is likely inefficnet")
        detector_normals = normal.(detector_triangles)
    end
    if isnothing(detector_bvh)
        println("Computing BVH. This is likely inefficnet")
        detector_bvh = build_bvh(detector_triangles)
    end
    if isnothing(detector_areas)
        println("Computing areas. This is likely inefficnet")
        detector_areas = area.(detector_triangles)
    end

    ## Construct initial state ##
    # Sample line defining neutrino trajectory
    d = rand(as, cs)
    revd = reverse(d)
    geometric_mask = geometric_triangle_weight(
        detector_triangles,
        d,
        detector_normals,
        detector_bvh
    )
    # Geometric is zero if all triangle are invalid
    if sum(geometric_mask)==0
        coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
        initial_state = Particle(pdg_id, NaN*u"GeV", coord, d)
        return null_event(-1, initial_state)
    end
    perp_areas = [-dot(norm.point, d.point) * area for (norm, area) in zip(detector_normals, detector_areas)]
    visible_areas = geometric_mask .* perp_areas
    tri = sample(detector_triangles, Weights(ustrip.(visible_areas)))
    x = sample(tri)
    p = Coordinate(x.point + revd.point * epsilon, cs)
    ray = Ray(p, revd)

    # Determine if trajectory is valid
    intersections = intersect_all(earth, ray)
    if length(intersections)==0
        coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
        initial_state = Particle(pdg_id, NaN*u"GeV", coord, d)
        return null_event(-2, initial_state)
    end
    # No intersections means it only passed through air
    mask = mask_helper(intersections, earth, revd)
    intersections = @views intersections[mask]
    # We won't bother simulating this because weight will be zero
    if sum(mask)==0
        coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
        initial_state = Particle(pdg_id, NaN*u"GeV", coord, d)
        return null_event(-3, initial_state)
    end

    # Sample energy and make initial state
    initial_energy = rand(pl)
    initial_state = Particle(pdg_id, initial_energy, p, d)

    ## Compute arrival state via TR interface ##
    close_state = taurunner_interface(initial_state, intersections)

    ## Compute final state ##
    # If we got charged lepton, just throw it in
    if abs(close_state.pdg_id)+1==abs(pdg_id)
        @show 42314234
        weight_params = WeightParameters(
            sum(visible_areas),
            pl,
            as,
            xs,
            initial_energy,
            close_state.energy,
            NaN * u"GeV",
            NaN * u"g/cm^2",
            NaN * u"g/cm^3"
        )
        return InjectionEvent(
            event_id,
            close_state,
            initial_state,
            close_state,
            weight_params
        )
    end

    if close_state.energy < minimum(xs.es)
        return InjectionEvent(event_id, close_state, initial_state, null_particle, null_params)
    end

    # If we got a neutrino, back trace and force an interaction
    eout = rand(xs, close_state.energy)
    pdg_out = close_state.pdg_id > 0 ? close_state.pdg_id-1 : close_state.pdg_id + 1
    range = particle_range(pdg_out, eout)
    distance, cd, density = find_vertex_distance(revd, range, intersections) 
    pout = Coordinate(first(intersections).point.point + revd.point * distance, cs)

    final_state = Particle(
        pdg_out,
        eout,
        pout,
        d
    )

    weight_params = WeightParameters(
        sum(visible_areas),
        pl,
        as,
        xs,
        initial_energy,
        close_state.energy,
        eout,
        cd |> u"g/cm^2",
        density
    )

    return InjectionEvent(
        event_id,
        close_state,
        initial_state,
        final_state,
        weight_params
    )

end

function fake_tr_interface(
    p::Particle{T},
    intersections::Vector{Intersection{T}}
) where {T<:Real}
    if rand() < 0.9
        return p
    else
        cs = CoordinateSystem(intersections[1].point)
        pdg_id = p.pdg_id > 0 ? p.pdg_id - 1 : p.pdg_id + 1
        position = Coordinate(p.position.point + 5u"km" * reverse(p.direction).point, cs)
        energy = min(2e7*u"GeV", p.energy/6)
        p = Particle(pdg_id, energy, position, p.direction)
        return p
    end
end

function select_detector_intersection(
    earth::Earth{T},
    revd::Direction{T},
    detector_triangles::Vector{Triangle{T}},
    detector_normals::Vector{Direction{T}},
) where {T<:Real}
    scales = [dot(revd.point, n.point) for n in detector_normals]

    faces_event = scales .> 0
    active_triangles = detector_triangles[faces_event]
    scaled_areas = area.(active_triangles) .* scales[faces_event]
    if length(active_triangles)==0
        return nothing, 0*u"m"^2
    end
    weights = Weights(ustrip.(scaled_areas))
    triangle = sample(active_triangles, weights)
    return sample(triangle), sum(scaled_areas)
end



#struct Injector
#    pdg_id::Int
#    powerlaw::PowerLaw
#    xs::CrossSection
#    anglesampler::UniformAngularSampler
#    injectionshape::AbstractInjectionShape
#    geo::Geometry
#end
#
#struct InjectionEvent
#    event_id::Int
#    entry_state::Particle
#    initial_state::Particle
#    final_state::Particle
#    genX::Float64
#    mc_weight::Float64
#    oneweight::Float64
#end
#
#function Injector(config::Dict, geo::Geometry)
#    pl = PowerLaw(
#        config["gamma"],
#        config["emin"] * units.GeV,
#        config["emax"] * units.GeV
#    )
#    xs = CrossSection(
#        config["xs_dir"],
#        config["xs_model"],
#        config["pdg_id"],
#        config["interaction"]
#    )
#    anglesampler = UniformAngularSampler(
#        deg2rad(config["thetamin"]),
#        deg2rad(config["thetamax"]),
#        deg2rad(config["phimin"]),
#        deg2rad(config["phimax"])
#    )
#
#    if "r_injection" in keys(config) && "l_endcap" in keys(config)
#        injectionshape = SymmetricInjectionCylinder(
#            config["r_injection"] * units.m,
#            config["l_endcap"] * units.m
#        )
#    elseif "length" in keys(config) && "width" in keys(config)
#        injectionshape = InjectionPlane(
#            config["length"] * units.m,
#            config["width"] * units.m,
#            geo.tambo_normal.proj
#        )
#    else
#        error("Unknown options for loading injection shape")
#    end
#    return Injector(config["pdg_id"], pl, xs, anglesampler, injectionshape, geo)
#end
#
#function inject_event(injector::Injector, event_id::Int, tr_seed::Int)
#    event = inject_event(
#        event_id,
#        injector.pdg_id,
#        injector.powerlaw,
#        injector.xs,
#        injector.anglesampler,
#        injector.injectionshape,
#        injector.geo,
#        tr_seed
#    )
#    return event
#end
#
#function sample_interaction_vertex(
#    endcap_distance::Float64,
#    closest_approach::SVector{3},
#    d::Direction,
#    range::Float64,
#    geo::Geometry
#)
#    track = Track(closest_approach, reverse(d), geo.box)
#    segments = computesegments(track, geo)
#    tot_X = endcapcolumndepth(track, endcap_distance, range, segments)
#    X = rand(Uniform(0.0, tot_X))
#    λ_int = inversecolumndepth(track, X, geo, segments)
#    p_int = track(λ_int)
#    return p_int, tot_X
#end
#
#"""
#    endcapcolumndepth(t::Track, l_endcap::Float64, range::Float64, segments::Vector{Segment})
#
#TBW
#"""
#function endcapcolumndepth(
#    t::Track,
#    l_endcap::Float64,
#    range::Float64,
#    segments::Vector{Segment}
#)
#    cd = totalcolumndepth(t, segments)
#    if t.norm <= l_endcap
#        return cd
#    end
#    cd_endcap = minimum([columndepth(t, l_endcap / t.norm, segments) + range, cd])
#    return cd_endcap
#end
#
#function determine_injection_start(
#    closest_approach::SVector{3},
#    boundary::SVector{3},
#    geo::Geometry
#)
#    track = Track(closest_approach, boundary)
#    segments = computesegments(track, geo)
#    if length(segments)==1
#        return closest_approach, false
#    end
#
#    start = closest_approach
#    saw_air, no_endcap = false, false
#    for segment in segments
#        saw_air = saw_air || segment.medium_name=="Air"
#        is_rock = segment.medium_name=="StandardRock"
#        right_side = dot(geo.plane.n̂.proj, segment.pstart) > 0
#        if saw_air && is_rock && right_side
#            start = segment.pstart
#            break
#        end
#    end
#    return start, no_endcap
#end
#
#"""
#
#TBW
#"""
#function inject_event(
#    event_id::Int,
#    ν_pdg::Int,
#    power_law::PowerLaw,
#    xs::CrossSection,
#    anglesampler::UniformAngularSampler,
#    cylinder::SymmetricInjectionCylinder,
#    geo::Geometry,
#    tr_seed::Int
#)
#    # Randomly sample direction
#    direction = Direction(rand(anglesampler)...)
#    # Rotation to plane perpindicular to direction
#    rotator = (RotX(direction.θ) * RotZ(π / 2 - direction.ϕ))'
#    # Find point of closest approach
#    closest_approach = rotator * rand(cylinder)
#    # Find where the particle entered the TAMBO region
#    xb = intersect(closest_approach, reverse(direction), geo.box)
#
#    # Sample initial neutrino energy
#    proposed_e_init = rand(power_law)
#    proposed_particle = Particle(ν_pdg, proposed_e_init, xb, direction)
#    particle_entry, physX = tr_propagate(proposed_particle, geo.tambo_offset.z, tr_seed)
#    # Set energy of neutrino when enters the box
#    e_final = rand(xs, particle_entry.energy)
#
#    # Find where to start counting CD from
#    injection_start, no_endcap = determine_injection_start(closest_approach, xb, geo)
#    l_endcap = cylinder.l_endcap
#    if no_endcap
#        l_endcap = 0.0
#    end
#    range = lepton_range(e_final, ν_pdg - sign(ν_pdg))
#    if range > 0
#        p_int, genX = sample_interaction_vertex(l_endcap, closest_approach, direction, range, geo)
#    else
#        p_int, genX = closest_approach, floatmin()
#    end
#    final_state = Particle(ν_pdg - sign(ν_pdg), e_final, p_int, direction)
#
#    mc_weight = 1 / p_mc(
#        proposed_e_init,
#        particle_entry.energy,
#        e_final,
#        direction.theta,
#        direction.phi,
#        p_int,
#        genX,
#        power_law,
#        xs,
#        anglesampler,
#        cylinder,
#        geo
#    )
#    oneweight = mc_weight * p_phys(
#        particle_entry.energy,
#        e_final,
#        genX,
#        p_int,
#        xs,
#        geo
#    )
#    if isnan(oneweight)
#        oneweight = 0.0
#    end
#
#    event = InjectionEvent(
#        event_id,
#        particle_entry,
#        proposed_particle,
#        final_state,
#        genX,
#        mc_weight,
#        oneweight
#    )
#    return event
#end
