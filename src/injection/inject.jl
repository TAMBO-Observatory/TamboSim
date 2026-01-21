# Error state codes for injection failures
const INJECTION_ERROR_NO_VISIBLE_TRIANGLES = -1
const INJECTION_ERROR_NO_INTERSECTIONS = -2
const INJECTION_ERROR_AIR_ONLY = -3

"""
    DetectorProperties{T}

A struct holding pre-computed detector properties for efficient injection.

Pre-computing these properties once and reusing them across many injection events
significantly improves performance compared to computing them on-the-fly.

# Fields
- `triangles::Vector{Triangle{T}}`: The detector triangles.
- `normals::Vector{Direction{T}}`: Pre-computed normals for each triangle.
- `bvh::BVHTree{T}`: Pre-built BVH acceleration structure.
- `areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}}`: Pre-computed areas for each triangle.
"""
struct DetectorProperties{T<:Real}
    triangles::Vector{Triangle{T}}
    normals::Vector{Direction{T}}
    bvh::BVHTree{T}
    areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}}
end

"""
    precompute_detector_properties(earth::Earth{T}) where {T<:Real}

Pre-computes detector properties from an Earth model for efficient injection.

This function should be called once before running multiple injection events.
The returned `DetectorProperties` can then be passed to `inject_event` to avoid
redundant computation of normals, BVH, and areas for each event.

# Arguments
- `earth::Earth{T}`: The Earth model containing the detector region.

# Returns
- `DetectorProperties{T}`: A struct containing pre-computed triangles, normals, BVH, and areas.

# Example
```julia
earth = Earth(...)
detector_props = precompute_detector_properties(earth)

# Now use in injection loop with the cleaner API
for i in 1:n_events
    result = inject_event(pdg, earth, as, pl, xs, detector_props)
end
```
"""
function precompute_detector_properties(earth::Earth{T}) where {T<:Real}
    triangles = earth.topography[earth.detector_region]
    normals = normal.(triangles)
    bvh = BVHTree(triangles)
    areas = area.(triangles)
    return DetectorProperties{T}(triangles, normals, bvh, areas)
end

"""
    create_null_result(
        pdg::Int,
        error_code::Int,
        cs::CoordinateSystem,
        ::Type{T}
    ) where {T<:Real}

Creates a null result tuple for failed injection events.

# Arguments
- `pdg`: The PDG ID of the particle.
- `error_code`: An error code indicating the failure reason.
- `cs`: The coordinate system for the null coordinate.
- `T`: The numeric type parameter.

# Returns
- A tuple of (initial_state, null_particle, null_particle, null_params).
"""
function create_null_result(
    pdg::Int,
    error_code::Int,
    cs::CoordinateSystem,
    ::Type{T}
) where {T<:Real}
    coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
    d = Direction([NaN, NaN, NaN], cs)
    initial_state = Particle(error_code, ParticleType(pdg), NaN*u"GeV", coord, d)
    return initial_state, Particle(T), Particle(T), null_params
end

"""
    sample_detector_point(
        triangles::Vector{Triangle{T}},
        normals::Vector{Direction{T}},
        areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}},
        bvh::BVHTree{T},
        d::Direction{T},
        cs::CoordinateSystem,
        epsilon
    ) where {T<:Real}

Samples a point on the detector surface based on visible area weighting.

# Returns
- `(point, visible_areas)` if successful, `(nothing, nothing)` if no visible triangles.
"""
function sample_detector_point(
    triangles::Vector{Triangle{T}},
    normals::Vector{Direction{T}},
    areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}},
    bvh::BVHTree{T},
    d::Direction{T},
    cs::CoordinateSystem,
    epsilon
) where {T<:Real}
    geometric_mask = geometric_triangle_weight(triangles, d, normals, bvh)

    if sum(geometric_mask) == 0
        return nothing, nothing
    end

    perp_areas = [-dot(norm.point, d.point) * a for (norm, a) in zip(normals, areas)]
    visible_areas = geometric_mask .* perp_areas
    tri = sample(triangles, Weights(ustrip.(visible_areas)))
    x = sample(tri)
    revd = reverse(d)
    p = Coordinate(x.point + revd.point * epsilon, cs)

    return p, visible_areas
end

"""
    validate_trajectory(
        earth::Earth,
        p::Coordinate{T},
        revd::Direction{T}
    ) where {T<:Real}

Validates a particle trajectory through the Earth model.

# Returns
- `(intersections, 0)` if valid, `(nothing, error_code)` if invalid.
"""
function validate_trajectory(
    earth::Earth,
    p::Coordinate{T},
    revd::Direction{T}
) where {T<:Real}
    ray = Ray(p, revd)
    intersections = intersect_all(earth, ray)

    if isempty(intersections)
        return nothing, INJECTION_ERROR_NO_INTERSECTIONS
    end

    mask = mask_helper(intersections, earth, revd)
    filtered = @views intersections[mask]

    if sum(mask) == 0
        return nothing, INJECTION_ERROR_AIR_ONLY
    end

    return filtered, 0
end

"""
    compute_final_state(
        close_state::Particle,
        xs::CrossSection,
        intersections,
        cs::CoordinateSystem,
        d::Direction{T}
    ) where {T<:Real}

Computes the final particle state after forcing an interaction.

# Returns
- `(final_state, eout, cd, density)` tuple with the interaction results.
"""
function compute_final_state(
    close_state::Particle,
    xs::CrossSection,
    intersections,
    cs::CoordinateSystem,
    d::Direction{T}
) where {T<:Real}
    revd = reverse(d)
    eout = rand(xs, close_state.energy)
    pdg_in = Int(close_state.pdg)
    pdg_out = pdg_in > 0 ? ParticleType(pdg_in - 1) : ParticleType(pdg_in + 1)

    if abs(Int(pdg_out)) == 15
        range = particle_vacuum_range(pdg_out, eout)
        distance, cd, density = find_vertex_distance_by_distance(revd, range, intersections)
    else
        range = particle_rock_range(eout, pdg_out)
        distance, cd, density = find_vertex_distance_by_cd(revd, range, intersections)
    end

    pout = Coordinate(first(intersections).point.point + revd.point * distance, cs)
    final_state = Particle(pdg_out, eout, pout, d)

    return final_state, eout, cd, density
end

"""
Internal implementation of inject_event containing the core logic.
"""
function _inject_event_impl(
    pdg::Int,
    earth::Earth,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    xs::CrossSection,
    detector_triangles::Vector{Triangle{T}},
    detector_normals::Vector{Direction{T}},
    detector_bvh::BVHTree{T},
    detector_areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}},
    epsilon,
    tr_seed
) where {T<:Real}
    cs = CoordinateSystem(earth)

    # Sample direction for neutrino trajectory
    d = rand(as, cs)

    # Sample point on detector surface
    p, visible_areas = sample_detector_point(
        detector_triangles, detector_normals, detector_areas,
        detector_bvh, d, cs, epsilon
    )

    if isnothing(p)
        return create_null_result(pdg, INJECTION_ERROR_NO_VISIBLE_TRIANGLES, cs, T)
    end

    # Validate trajectory through Earth
    revd = reverse(d)
    intersections, error_code = validate_trajectory(earth, p, revd)

    if isnothing(intersections)
        return create_null_result(pdg, error_code, cs, T)
    end

    # Sample energy and create initial state
    initial_energy = rand(pl)
    initial_state = Particle(ParticleType(pdg), initial_energy, p, d)

    # Propagate through Earth via TauRunner interface
    close_state = taurunner_interface(initial_state, intersections, tr_seed)

    # Handle charged lepton output (no forced interaction needed)
    if abs(Int(close_state.pdg)) + 1 == abs(Int(pdg))
        weight_params = WeightParameters(
            sum(visible_areas),
            pl, as, xs,
            initial_energy,
            close_state.energy,
            NaN * u"GeV",
            NaN * u"g/cm^2",
            NaN * u"g/cm^3"
        )
        return initial_state, close_state, close_state, weight_params
    end

    # Check if energy is below cross-section threshold
    if close_state.energy < minimum(xs.es)
        return initial_state, close_state, Particle(T), null_params
    end

    # Force interaction for neutrino output
    final_state, eout, cd, density = compute_final_state(
        close_state, xs, intersections, cs, d
    )

    weight_params = WeightParameters(
        sum(visible_areas),
        pl, as, xs,
        initial_energy,
        close_state.energy,
        eout,
        cd |> u"g/cm^2",
        density
    )

    return initial_state, close_state, final_state, weight_params
end

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
    detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing}=nothing,
    epsilon=1e-6*u"m",
    tr_seed=nothing
) where {T<:Real}
    # Compute detector properties if not provided (inefficient for repeated calls)
    if isnothing(detector_triangles)
        detector_triangles = earth.topography[earth.detector_region]
    end
    if isnothing(detector_normals)
        @warn "Computing normals on-the-fly. Use precompute_detector_properties() for better performance." maxlog=1
        detector_normals = normal.(detector_triangles)
    end
    if isnothing(detector_bvh)
        @warn "Computing BVH on-the-fly. Use precompute_detector_properties() for better performance." maxlog=1
        detector_bvh = BVHTree(detector_triangles)
    end
    if isnothing(detector_areas)
        @warn "Computing areas on-the-fly. Use precompute_detector_properties() for better performance." maxlog=1
        detector_areas = area.(detector_triangles)
    end

    return _inject_event_impl(
        pdg, earth, as, pl, xs,
        detector_triangles, detector_normals, detector_bvh, detector_areas,
        epsilon, tr_seed
    )
end

"""
    inject_event(
        pdg::Int,
        earth::Earth,
        as::UniformAngularSampler,
        pl::UnitfulPowerLawSampler,
        xs::CrossSection,
        detector_props::DetectorProperties{T};
        epsilon=1e-6*u"m",
        tr_seed=nothing
    ) where {T<:Real}

Simulates injection using pre-computed detector properties.

This is the recommended method for batch injection as it avoids recomputing
detector geometry for each event.

# Example
```julia
earth = Earth(...)
detector_props = precompute_detector_properties(earth)

for i in 1:n_events
    result = inject_event(pdg, earth, as, pl, xs, detector_props)
end
```
"""
function inject_event(
    pdg::Int,
    earth::Earth,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    xs::CrossSection,
    detector_props::DetectorProperties{T};
    epsilon=1e-6*u"m",
    tr_seed=nothing
) where {T<:Real}
    return _inject_event_impl(
        pdg, earth, as, pl, xs,
        detector_props.triangles, detector_props.normals,
        detector_props.bvh, detector_props.areas,
        epsilon, tr_seed
    )
end
