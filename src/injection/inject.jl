function inject_event(
    pdg::Int,
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
    tr_seed=nothing
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
        initial_state = Particle(-1, ParticleType(pdg), NaN*u"GeV", coord, d)
        return initial_state, Particle(T), Particle(T), null_params
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
        initial_state = Particle(-2, ParticleType(pdg), NaN*u"GeV", coord, d)
        return initial_state, Particle(T), Particle(T), null_params
    end
    # No intersections means it only passed through air
    mask = mask_helper(intersections, earth, revd)
    intersections = @views intersections[mask]
    # We won't bother simulating this because weight will be zero
    if sum(mask)==0
        coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
        initial_state = Particle(-3, ParticleType(pdg), NaN*u"GeV", coord, d)
        return initial_state, Particle(T), Particle(T), null_params
    end

    # Sample energy and make initial state
    initial_energy = rand(pl)
    initial_state = Particle(ParticleType(pdg), initial_energy, p, d)

    ## Compute arrival state via TR interface ##
    close_state = taurunner_interface(initial_state, intersections, tr_seed)

    ## Compute final state ##
    # If we got charged lepton, just throw it in
    if abs(Int(close_state.pdg))+1==abs(Int(pdg))
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
        return initial_state, close_state, close_state, weight_params
    end

    if close_state.energy < minimum(xs.es)
        return initial_state, close_state, Particle(T), null_params
    end

    # If we got a neutrino, back trace and force an interaction
    eout = rand(xs, close_state.energy)
    pdg_out = Int(close_state.pdg) > 0 ? ParticleType(Int(close_state.pdg)-1) : ParticleType(Int(close_state.pdg) + 1)
    if abs(Int(pdg_out))==15
        range = particle_vacuum_range(pdg_out, eout)
        distance, cd, density = find_vertex_distance_by_distance(revd, range, intersections) 
    else
        range = particle_rock_range(eout, pdg_out)
        distance, cd, density = find_vertex_distance_by_cd(revd, range, intersections) 
    end
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

    return initial_state, close_state, final_state, weight_params

end
