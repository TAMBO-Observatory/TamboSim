"""
    inject_event(
        pdg::Int,
        earth::Earth,
        as::UniformAngularSampler,
        pl::UnitfulPowerLawSampler,
        xs::CrossSection;
        detector_triangles::Union{Vector{Triangle{T}}, Nothing}=nothing,
        detector_normals::Union{Vector{Direction{T}}, Nothing}=nothing,
        detector_bvh::Union{BVHTree{T}, Nothing}=nothing,
        detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing}=nothing,
        epsilon=1e-6*u"m",
        tr_seed=nothing
    ) -> Tuple{Particle, Particle, Particle, WeightParameters}

Simulates the injection and initial interaction of a particle (e.g., neutrino) into the Earth model.

This function performs several steps:
1. Samples a neutrino trajectory based on `as` and determines the detector element it targets.
2. Constructs the initial neutrino `Particle` state, sampling its energy from `pl`.
3. Propagates the neutrino through the Earth's media using an interface (e.g., `taurunner_interface`)
   to determine its state near the interaction point (`close_state`).
4. If the `close_state` is a neutrino, it forces an interaction (based on `xs`) and
   determines the final state (`final_state`) and its interaction vertex.
5. Calculates `WeightParameters` for the event.

# Arguments
- `pdg::Int`: The PDG ID of the injected particle (e.g., neutrino).
- `earth::Earth`: The Earth model, including topography and material densities.
- `as::UniformAngularSampler`: Sampler for the angular distribution of injected particles.
- `pl::UnitfulPowerLawSampler`: Sampler for the energy distribution of injected particles.
- `xs::CrossSection`: Cross-section data for particle interactions.
- `detector_triangles::Union{Vector{Triangle{T}}, Nothing}`: Optional pre-computed detector triangles. If `nothing`, derived from `earth`.
- `detector_normals::Union{Vector{Direction{T}}, Nothing}`: Optional pre-computed detector normals. If `nothing`, computed from `detector_triangles`.
- `detector_bvh::Union{BVHTree{T}, Nothing}`: Optional pre-computed BVH for detector triangles. If `nothing`, built from `detector_triangles`.
- `detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing}`: Optional pre-computed detector areas. If `nothing`, computed from `detector_triangles`.
- `epsilon`: A small offset distance to avoid self-intersections when casting rays (default: 1e-6 m).
- `tr_seed`: Seed for the `taurunner_interface` (if used).

# Returns
- `Tuple{Particle, Particle, Particle, WeightParameters}`:
    - `initial_state`: The initial `Particle` state at injection.
    - `close_state`: The `Particle` state just before the final interaction or at detector entry.
    - `final_state`: The `Particle` state after interaction, or the `close_state` if it's a charged lepton.
    - `weight_params`: Parameters used for calculating event weights.
"""
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

"""
    fake_tr_interface(p::Particle{T}, intersections::Vector{Intersection{T}}) -> Particle{T}

A placeholder or "fake" interface for simulating particle propagation through the Earth.

This function randomly decides whether the input particle `p` interacts. If it does not,
the original particle is returned. If it interacts, a new particle state is generated
with a modified PDG ID, position, and energy, simulating a decay or interaction.
This is not a physically accurate simulation but serves as a test or simplified model.

# Arguments
- `p::Particle{T}`: The initial `Particle` object.
- `intersections::Vector{Intersection{T}}`: A list of `Intersection` objects (used for coordinate system reference).

# Returns
- `Particle{T}`: The propagated or interacted `Particle` object.
"""
function fake_tr_interface(
    p::Particle{T},
    intersections::Vector{Intersection{T}}
) where {T<:Real}
    if rand() < 0.9
        return p
    else
        cs = CoordinateSystem(intersections[1].point)
        pdg = p.pdg > 0 ? p.pdg - 1 : p.pdg + 1
        position = Coordinate(p.position.point + 5u"km" * reverse(p.direction).point, cs)
        energy = min(2e7*u"GeV", p.energy/6)
        p = Particle(pdg, energy, position, p.direction)
        return p
    end
end

"""
    select_detector_intersection(
        earth::Earth{T},
        revd::Direction{T},
        detector_triangles::Vector{Triangle{T}},
        detector_normals::Vector{Direction{T}},
    ) -> Tuple{Union{Coordinate, Nothing}, Quantity{T,ldim^2,typeof(u"m^2")}}

Selects a random intersection point on a detector surface, weighted by the scaled area of active triangles.

This function first identifies `detector_triangles` that are "active" (facing the incoming `revd` direction).
It then scales their areas by the dot product with the incoming direction and samples one of these triangles
based on these scaled areas. Finally, it samples a point uniformly within the chosen triangle.

# Arguments
- `earth::Earth{T}`: The Earth model (not directly used, but provides context for coordinate system).
- `revd::Direction{T}`: The reverse direction of the incoming particle, used to determine which faces are active.
- `detector_triangles::Vector{Triangle{T}}`: The triangles defining the detector surface.
- `detector_normals::Vector{Direction{T}}`: The normal vectors for each detector triangle.

# Returns
- `Tuple{Union{Coordinate, Nothing}, Quantity{T,ldim^2,typeof(u"m^2")}}`: A tuple containing:
    - A `Coordinate` object representing the sampled intersection point on a detector triangle, or `nothing` if no active triangles are found.
    - The sum of the scaled areas of all active triangles.
"""
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
