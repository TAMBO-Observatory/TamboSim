# Error state codes for injection failures
const INJECTION_ERROR_NO_VISIBLE_TRIANGLES = -1
const INJECTION_ERROR_NO_INTERSECTIONS = -2
const INJECTION_ERROR_AIR_ONLY = -3
const INJECTION_ERROR_INSUFFICIENT_INTERSECTIONS = -4
const INJECTION_ERROR_RUNTIME = -5

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
    precompute_detector_properties(topography, detector_region) -> DetectorProperties

Pre-computes detector properties for efficient injection.

# Arguments
- `topography`: Full topography mesh (vector of triangles).
- `detector_region`: Integer indices of detector triangles within `topography`.

# Returns
- `DetectorProperties{T}`: Pre-computed triangles, normals, BVH, and areas.
"""
function precompute_detector_properties(
    topography::Vector{Triangle{T}},
    detector_region
) where {T<:Real}
    triangles = topography[detector_region]
    normals = normal.(triangles)
    bvh = BVHTree(triangles)
    areas = area.(triangles)
    return DetectorProperties{T}(triangles, normals, bvh, areas)
end

"""
    create_null_result(
        pdg::Int,
        error_code::Int,
        d::Direction{T},
        cs::CoordinateSystem,
        ::Type{T}
    ) where {T<:Real}

Creates a null result tuple for failed injection events.

# Arguments
- `pdg`: The PDG ID of the particle.
- `error_code`: An error code indicating the failure reason.
- `d`: The sampled direction for this event (preserved in the null result).
- `cs`: The coordinate system for the null coordinate.
- `T`: The numeric type parameter.

# Returns
- A tuple of (initial_state, null_particle, null_particle, nothing).
"""
function create_null_result(
    pdg::Int,
    error_code::Int,
    d::Direction{T},
    cs::CoordinateSystem,
    ::Type{T}
) where {T<:Real}
    coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
    initial_state = Particle(error_code, ParticleType(pdg), NaN*u"GeV", coord, d)
    return initial_state, Particle(T), Particle(T), nothing
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
    validate_trajectory(prem, bvh, detector_region, p, revd) -> (intersections, error_code)

Validates a particle trajectory through the Earth model.

# Returns
- `(intersections, 0)` if valid, `(nothing, error_code)` if invalid.
"""
function validate_trajectory(
    prem,
    bvh::BVHTree{T},
    detector_region,
    p::Coordinate{T},
    revd::Direction{T}
) where {T<:Real}
    ray = Ray(p, revd)
    intersections = intersect_all(prem, bvh, ray)

    if isempty(intersections)
        return nothing, INJECTION_ERROR_NO_INTERSECTIONS
    end

    mask = mask_helper(intersections, detector_region, revd)
    filtered = @views intersections[mask]

    if sum(mask) == 0
        return nothing, INJECTION_ERROR_AIR_ONLY
    end

    if length(filtered) < 2
        return nothing, INJECTION_ERROR_INSUFFICIENT_INTERSECTIONS
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
function _inject_neutrino_event_impl(
    pdg::Int,
    prem,
    bvh::BVHTree{T},
    cs::CoordinateSystem{T},
    detector_region,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    xs::CrossSection,
    detector_triangles::Vector{Triangle{T}},
    detector_normals::Vector{Direction{T}},
    detector_bvh::BVHTree{T},
    detector_areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}},
    epsilon,
    tr_seed,
) where {T<:Real}

    # Sample direction for neutrino trajectory
    d = rand(as, cs)

    # Sample point on detector surface
    p, visible_areas = sample_detector_point(
        detector_triangles, detector_normals, detector_areas,
        detector_bvh, d, cs, epsilon
    )

    if isnothing(p)
        return create_null_result(pdg, INJECTION_ERROR_NO_VISIBLE_TRIANGLES, d, cs, T)
    end

    # Validate trajectory through Earth
    revd = reverse(d)
    intersections, error_code = validate_trajectory(prem, bvh, detector_region, p, revd)

    if isnothing(intersections)
        return create_null_result(pdg, error_code, d, cs, T)
    end

    # Sample energy and create initial state
    initial_energy = rand(pl)
    initial_state = Particle(ParticleType(pdg), initial_energy, p, d)

    local close_state, final_state, point
    try
        # Propagate through Earth via TauRunner interface
        close_state = taurunner_interface(initial_state, intersections, tr_seed)

        # Handle null particle from failed propagation
        if isnan(close_state.energy)
            return create_null_result(pdg, INJECTION_ERROR_RUNTIME, d, cs, T)
        end

        theta, phi = cart_to_sph(d)
        area = sum(visible_areas)

        # Handle charged lepton output (no forced interaction needed):
        # the neutrino was converted upstream during Earth transit.
        if abs(Int(close_state.pdg)) + 1 == abs(Int(pdg))
            point = UpstreamNeutrinoInteractionPoint(initial_energy, theta, phi, area)
            return initial_state, close_state, close_state, point
        end

        # Check if energy is below cross-section threshold
        if close_state.energy < minimum(xs.es)
            return initial_state, close_state, Particle(T), nothing
        end

        # Force interaction for neutrino output
        final_state, eout, cd, density = compute_final_state(
            close_state, xs, intersections, cs, d
        )

        sigma  = xs(close_state.energy)
        dsigma = xs(close_state.energy, eout)
        point = ForcedNeutrinoInteractionPoint(
            initial_energy, theta, phi, area,
            cd |> u"g/cm^2", density, sigma, dsigma,
        )
    catch e
        @warn "Runtime error during event injection, returning null result" exception=(e, catch_backtrace())
        return create_null_result(pdg, INJECTION_ERROR_RUNTIME, d, cs, T)
    end

    return initial_state, close_state, final_state, point
end

"""
    inject_event(
        pdg::Int,
        prem,
        bvh::BVHTree{T},
        cs::CoordinateSystem{T},
        detector_region,
        topography::Vector{Triangle{T}},
        as::UniformAngularSampler,
        pl::UnitfulPowerLawSampler,
        xs::CrossSection;
        detector_triangles::Union{Vector{Triangle{T}}, Nothing}=nothing,
        detector_normals::Union{Vector{Direction{T}}, Nothing}=nothing,
        detector_bvh::Union{BVHTree{T}, Nothing}=nothing,
        detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing}=nothing,
        epsilon=1e-6*u"m",
        tr_seed=nothing
    ) -> Tuple{Particle, Particle, Particle, Union{PhaseSpacePoint, Nothing}}

Simulates the injection and initial interaction of a neutrino into the Earth.

This function performs several steps:
1. Samples a neutrino trajectory based on `as` and determines the detector element it targets.
2. Constructs the initial neutrino `Particle` state, sampling its energy from `pl`.
3. Propagates the neutrino through the Earth's media using an interface (e.g., `taurunner_interface`)
   to determine its state near the interaction point (`close_state`).
4. If the `close_state` is a neutrino, it forces an interaction (based on `xs`) and
   determines the final state (`final_state`) and its interaction vertex.
5. Builds a `PhaseSpacePoint` recording the per-event phase-space coordinates
   needed for downstream weighting.

# Arguments
- `pdg::Int`: The PDG ID of the injected particle (e.g., neutrino).
- `prem`: PREM-style radial density model used by the propagation interface.
- `bvh::BVHTree{T}`: BVH over the full topography mesh, used for trajectory ↔ surface intersection.
- `cs::CoordinateSystem{T}`: ECEF-anchored coordinate system the geometry lives in.
- `detector_region`: indices of the topography triangles that make up the detector surface.
- `topography::Vector{Triangle{T}}`: full triangulated terrain mesh.
- `as::UniformAngularSampler`: Sampler for the angular distribution of injected particles.
- `pl::UnitfulPowerLawSampler`: Sampler for the energy distribution of injected particles.
- `xs::CrossSection`: Cross-section data for particle interactions.
- `detector_triangles::Union{Vector{Triangle{T}}, Nothing}`: Optional pre-computed detector triangles. If `nothing`, derived from `topography[detector_region]`.
- `detector_normals::Union{Vector{Direction{T}}, Nothing}`: Optional pre-computed detector normals. If `nothing`, computed from `detector_triangles`.
- `detector_bvh::Union{BVHTree{T}, Nothing}`: Optional pre-computed BVH for detector triangles. If `nothing`, built from `detector_triangles`.
- `detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing}`: Optional pre-computed detector areas. If `nothing`, computed from `detector_triangles`.
- `epsilon`: A small offset distance to avoid self-intersections when casting rays (default: 1e-6 m).
- `tr_seed`: Seed for the `taurunner_interface` (if used).

# Returns
- `Tuple{Particle, Particle, Particle, Union{PhaseSpacePoint, Nothing}}`:
    - `initial_state`: The initial `Particle` state at injection.
    - `close_state`: The `Particle` state just before the final interaction or at detector entry.
    - `final_state`: The `Particle` state after interaction, or the `close_state` if it's a charged lepton.
    - `point`: A `PhaseSpacePoint` (forced-CC or upstream-converted) when the event
      succeeded, otherwise `nothing` (failed/below-threshold paths).
"""
function inject_event(
    pdg::Int,
    prem,
    bvh::BVHTree{T},
    cs::CoordinateSystem{T},
    detector_region,
    topography::Vector{Triangle{T}},
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    xs::CrossSection;
    detector_triangles::Union{Vector{Triangle{T}}, Nothing}=nothing,
    detector_normals::Union{Vector{Direction{T}}, Nothing}=nothing,
    detector_bvh::Union{BVHTree{T}, Nothing}=nothing,
    detector_areas::Union{Vector{Quantity{T,ldim^2,typeof(u"m^2")}}, Nothing}=nothing,
    epsilon=1e-6*u"m",
    tr_seed=nothing,
) where {T<:Real}
    # Compute detector properties if not provided (inefficient for repeated calls)
    if isnothing(detector_triangles)
        detector_triangles = topography[detector_region]
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

    return _inject_neutrino_event_impl(
        pdg, prem, bvh, cs, detector_region, as, pl, xs,
        detector_triangles, detector_normals, detector_bvh, detector_areas,
        epsilon, tr_seed
    )
end

"""
    inject_event(
        pdg::Int,
        prem,
        bvh::BVHTree{T},
        cs::CoordinateSystem{T},
        detector_region,
        as::UniformAngularSampler,
        pl::UnitfulPowerLawSampler,
        xs::CrossSection,
        detector_props::DetectorProperties{T};
        epsilon=1e-6*u"m",
        tr_seed=nothing
    ) where {T<:Real}

Simulates injection using pre-computed detector properties.

This is the recommended method for batch injection: detector geometry
(triangles, normals, BVH, areas) is built once via [`precompute_detector_properties`](@ref)
and reused across events.

# Example
```julia
detector_props = precompute_detector_properties(topography, detector_region)

for i in 1:n_events
    result = inject_event(pdg, prem, bvh, cs, detector_region, as, pl, xs, detector_props)
end
```
"""
function inject_event(
    pdg::Int,
    prem,
    bvh::BVHTree{T},
    cs::CoordinateSystem{T},
    detector_region,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    xs::CrossSection,
    detector_props::DetectorProperties{T};
    epsilon=1e-6*u"m",
    tr_seed=nothing,
) where {T<:Real}
    return _inject_neutrino_event_impl(
        pdg, prem, bvh, cs, detector_region, as, pl, xs,
        detector_props.triangles, detector_props.normals,
        detector_props.bvh, detector_props.areas,
        epsilon, tr_seed
    )
end

"""
    inject_proton_event(
        bvh::BVHTree{T},
        cs::CoordinateSystem{T},
        detector_region,
        as::UniformAngularSampler,
        pl::UnitfulPowerLawSampler,
        detector_props::DetectorProperties{T};
        altitude::Quantity=50.0u"km",
        epsilon=1e-6*u"m"
    ) where {T<:Real}

Simulates the injection of a downgoing cosmic ray proton.

Unlike neutrino injection, this skips TauRunner/PROPOSAL and directly produces
a proton particle suitable for CORSIKA shower simulation. The proton starts at
the specified altitude above the detector, traveling downward along the sampled
direction.

# Steps
1. Samples a direction using the angular sampler.
2. Samples a point on the detector surface using `sample_detector_point`.
3. Traces back along the trajectory to find the starting position at the given altitude.
4. Samples energy from the power-law sampler.

# Arguments
- `bvh::BVHTree{T}`: BVH over the full topography mesh.
- `cs::CoordinateSystem{T}`: ECEF-anchored coordinate system.
- `detector_region`: indices of the topography triangles forming the detector surface.
- `as::UniformAngularSampler`: Sampler for the angular distribution.
- `pl::UnitfulPowerLawSampler`: Sampler for the energy distribution.
- `detector_props::DetectorProperties{T}`: Pre-computed detector properties.
- `altitude::Quantity`: Starting altitude for the proton (default: 50 km).
- `epsilon`: Small offset to avoid self-intersections (default: 1e-6 m).

# Returns
- `(initial_proton::Particle, final_proton::Particle, visible_areas, passes_through_rock)`:
  `initial_proton` is at the detector surface point (before backtracing),
  `final_proton` is at the specified altitude (after backtracing, ready for CORSIKA).
  If no visible triangles exist, both particles have `NaN` energy and `visible_areas` is `nothing`.
"""
function inject_proton_event(
    bvh::BVHTree{T},
    cs::CoordinateSystem{T},
    detector_region,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    detector_props::DetectorProperties{T};
    altitude::Quantity=50.0u"km",
    epsilon=1e-6*u"m",
) where {T<:Real}
    d = rand(as, cs)

    # Same detector point sampling as neutrino
    p, visible_areas = sample_detector_point(
        detector_props.triangles, detector_props.normals, detector_props.areas,
        detector_props.bvh, d, cs, epsilon
    )
    if isnothing(p)
        coord = Coordinate([NaN, NaN, NaN].*u"m", cs)
        dir = Direction([NaN, NaN, NaN], cs)
        nan_particle = Particle(INJECTION_ERROR_NO_VISIBLE_TRIANGLES, PPlus, NaN*u"GeV", coord, dir)
        return nan_particle, nan_particle, false, nothing
    end

    # Trace back along trajectory to reach the specified altitude above the curved Earth's
    # surface. For nearly horizontal directions, the flat-Earth approximation (z = altitude)
    # fails because the injection point can be thousands of km from the detector, where
    # Earth's curvature significantly changes the true altitude. Instead, solve for the
    # parameter t such that the ECEF distance from Earth's center equals R_earth + altitude.
    revd = reverse(d)
    alt_m = uconvert(u"m", altitude)

    # Convert detector surface point and reversed direction to ECEF
    ecef_p = convert(ecefcoordinates, p)
    ecef_revd = convert(ecefcoordinates, revd)
    a = ecef_p.point       # ECEF position (meters)
    b = ecef_revd.point    # ECEF direction (unitless)

    # Earth radius from the detector CS origin
    rearth = sqrt(cs.origin[1]^2 + cs.origin[2]^2 + cs.origin[3]^2)
    target_r = rearth + alt_m

    # Solve ||a + b*t||^2 = target_r^2
    # => t^2 + 2(a·b)t + (||a||^2 - target_r^2) = 0
    a_dot_b = a[1]*b[1] + a[2]*b[2] + a[3]*b[3]
    a_sq = a[1]^2 + a[2]^2 + a[3]^2
    discriminant = a_dot_b^2 - a_sq + target_r^2
    t = -a_dot_b + sqrt(discriminant)

    proton_position = Coordinate(p.point + revd.point * t, cs)

    energy = rand(pl)
    initial_proton = Particle(PPlus, energy, p, d)
    final_proton = Particle(PPlus, energy, proton_position, d)

    # Check if the proton path passes through rock (mountains between injection and detector)
    forward_ray = Ray(proton_position, d)
    topo_hits = intersect_all(bvh, forward_ray)
    detector_indices = Set(detector_region)
    diff = proton_position.point - p.point
    path_len = sqrt(diff[1]^2 + diff[2]^2 + diff[3]^2)
    # Check if any non-detector topography triangle (i.e. a mountain) is hit
    # within the path from the injection point to the detector surface
    passes_through_rock = any(topo_hits) do ix
        ix.index ∉ detector_indices && ix.distance < path_len
    end

    theta, phi = cart_to_sph(d)
    point = SurfaceCRPoint(energy, theta, phi, sum(visible_areas))

    return initial_proton, final_proton, passes_through_rock, point
end

function _setup_injection(frames::TamboFrames, config::Dict, prefix::String, fname::String)
    haskey(config, "nevent") || error("$fname config must contain \"nevent\"")
    _ensure_earth_loaded!(frames)
    g_frame = _get_last_frame(frames, 'G')
    m_parents = Dict{Char,Frame}('G' => g_frame)
    for s in ('C', 'D')
        f = _get_last_frame(frames, s; required=false)
        f !== nothing && (m_parents[s] = f)
    end
    config_with_hash = merge(config, Dict("geometry_hash" => UInt(g_frame["geometry_hash"])))
    m_frame = Frame('M', Dict{String,Any}(prefix => config_with_hash), m_parents)
    push!(frames, m_frame)
    q_parents = Dict{Char,Frame}('M' => m_frame)
    for s in ('G', 'C', 'D')
        haskey(m_parents, s) && (q_parents[s] = m_parents[s])
    end
    q_frames = Frame[]
    for idx in 1:config["nevent"]
        q_frame = Frame('Q', Dict{String,Any}(), q_parents)
        q_frame["event_id"] = idx
        push!(q_frames, q_frame)
    end
    append!(frames, q_frames)
    return g_frame, m_frame, q_frames
end

"""
    inject!(frames::TamboFrames, config::Dict; prefix::String="injection")

Unified injection entrypoint. Reads `config["strategy"]` and dispatches
to the matching backend:

- `"NeutrinoInjection"`   → [`inject_neutrinos!`](@ref)
- `"CosmicRayInjection"`  → [`inject_protons!`](@ref)

Errors loudly if `strategy` is missing or not recognized. The backends
remain callable directly for tests and power users.
"""
function inject!(
    frames::TamboFrames,
    config::Dict;
    prefix::String="injection"
)
    haskey(config, "strategy") || error(
        "inject!: injection config is missing required `strategy` field. " *
        "Set it to one of \"NeutrinoInjection\" or \"CosmicRayInjection\"."
    )
    strategy = config["strategy"]
    if strategy == "NeutrinoInjection"
        return inject_neutrinos!(frames, config; prefix=prefix)
    elseif strategy == "CosmicRayInjection"
        return inject_protons!(frames, config; prefix=prefix)
    else
        error(
            "inject!: unknown strategy \"$strategy\". " *
            "Expected \"NeutrinoInjection\" or \"CosmicRayInjection\"."
        )
    end
end

"""
    inject_neutrinos!(frames::TamboFrames, config::Dict; prefix::String="injection")

Inject neutrino primaries into a TamboFrames container. Mutates `frames`
in place by:

1. Appending one new M frame, with the parsed `config` snapshotted on it
   under `prefix` (default `"injection"`) for provenance.
2. Appending `config["nevent"]` empty Q frames, each tagged with a
   sequential `event_id` and parented to the new M frame.
3. For every Q frame, sampling a primary `(energy, direction)` from
   `config`'s power-law and angular ranges, tracing it through the
   geometry, and writing the resulting injection states and a
   `PhaseSpacePoint` back onto the frame:

   - `<prefix>_initial_state` — the hypothetical primary at the
     detector-surface sampling point with source-spectrum energy.
   - `<prefix>_close_state`   — TauRunner's output: the actual neutrino
     reaching that point after Earth absorption / regeneration.
   - `<prefix>_final_state`   — the forced CC interaction vertex inside
     rock (omitted when no rock crossing is found along the trajectory).
   - `phase_space_point`      — per-event phase-space coordinates consumed
     downstream by `oneweight` / `oneweights`.

# Arguments
- `frames::TamboFrames`: the container to mutate. Must already contain G,
  C, and D frames (typically loaded from a GCD bundle).
- `config::Dict`: parsed `[injection]` TOML table. Must contain `"nevent"`;
  consults `"pdg"`, `"emin"`, `"emax"`, `"gamma"`, `"thetamin/max"`,
  `"phimin/max"`, `"xs_location"`, and `"pinecone"` (RNG seed).

# Keyword arguments
- `prefix::String`: namespace under which states and the config snapshot
  are stored. Default `"injection"`.
"""
function inject_neutrinos!(
    frames::TamboFrames,
    config::Dict;
    prefix::String="injection"
)
    g_frame, m_frame, q_frames = _setup_injection(frames, config, prefix, "inject_neutrinos!")
    d_frame = m_frame.d_frame

    prem            = g_frame["prem"]
    bvh             = g_frame["bvh"]
    cs              = g_frame["cs"]
    topography      = g_frame["topography"]
    detector_region = d_frame["detector_region"]
    detector_bvh    = d_frame["detector_bvh"]

    pl = UnitfulPowerLawSampler(
        config["gamma"],
        config["emin"] * u"GeV",
        config["emax"] * u"GeV"
    )
    as = UniformAngularSampler(
        deg2rad(config["thetamin"]),
        deg2rad(config["thetamax"]),
        deg2rad(config["phimin"]),
        deg2rad(config["phimax"]),
    )
    cross_section = CrossSection(config["xs_location"])
    detector_triangles = detector_bvh.triangles
    detector_areas  = area.(detector_triangles)
    detector_normals = normal.(detector_triangles)
    Random.seed!(config["pinecone"])

    @llama_showprogress "Injecting" for frame in q_frames
        tr_seed = rand(UInt32)
        istate, cstate, fstate, point = inject_event(
            config["pdg"],
            prem, bvh, cs, detector_region, topography,
            as, pl, cross_section;
            detector_areas=detector_areas,
            detector_normals=detector_normals,
            detector_bvh=detector_bvh,
            tr_seed=tr_seed,
        )
        frame["$(prefix)_initial_state"] = istate
        if !isnan(cstate.energy)
            frame["$(prefix)_close_state"] = cstate
        end
        if !isnan(fstate.energy)
            frame["$(prefix)_final_state"] = fstate
        end
        point === nothing || (frame["phase_space_point"] = point)
    end
end

"""
    inject_protons!(frames::TamboFrames, config::Dict; prefix::String="injection")

Inject downgoing cosmic-ray protons onto the detector surface. Mutates
`frames` by appending one new M frame (with `config` snapshotted under
`prefix` for provenance) and `config["nevent"]` Q frames. Each Q frame
carries:

- `<prefix>_initial_state` — proton at the sampled point on the detector surface
- `<prefix>_final_state` — proton backtraced to `config["altitude"]` above
  Earth, ready for CORSIKA injection
- `particle_passes_through_rock::Bool` — whether the back-traced ray clipped
  the topography on its way up
- `phase_space_point::SurfaceCRPoint` — surface-injection phase-space
  coordinates consumed downstream by `oneweight` / `oneweights`.

Q frames where the angular sampler hit no visible detector triangles are
silently skipped and have none of the above keys written.

Unlike [`inject!`](@ref), this does not force a CC interaction — every
sampled proton produces a shower at its sampled position by construction,
so the close- and final-state-of-the-CC-vertex machinery is not needed.

# Arguments
- `frames::TamboFrames`: container to mutate; must already contain G, C, D.
- `config::Dict`: parsed config table. Must contain `"nevent"`.

# Keyword arguments
- `prefix::String`: namespace for the config snapshot and per-Q-frame
  state keys. Default `"injection"`.
"""
function inject_protons!(
    frames::TamboFrames,
    config::Dict;
    prefix::String="injection"
)
    g_frame, m_frame, q_frames = _setup_injection(frames, config, prefix, "inject_protons!")
    d_frame = m_frame.d_frame

    bvh             = g_frame["bvh"]
    cs              = g_frame["cs"]
    topography      = g_frame["topography"]
    detector_region = d_frame["detector_region"]

    pl = UnitfulPowerLawSampler(
        config["gamma"],
        config["emin"] * u"GeV",
        config["emax"] * u"GeV"
    )
    as = UniformAngularSampler(
        deg2rad(config["thetamin"]),
        deg2rad(config["thetamax"]),
        deg2rad(config["phimin"]),
        deg2rad(config["phimax"]),
    )
    altitude = get(config, "altitude", 50.0) * u"km"
    detector_props = precompute_detector_properties(topography, detector_region)
    Random.seed!(config["pinecone"])

    @llama_showprogress "Injecting protons" for frame in q_frames
        initial_proton, final_proton, passes_through_rock, point = inject_proton_event(
            bvh, cs, detector_region, as, pl, detector_props;
            altitude=altitude,
        )
        if !isnan(initial_proton.energy)
            frame["$(prefix)_initial_state"] = initial_proton
            frame["$(prefix)_final_state"] = final_proton
            frame["particle_passes_through_rock"] = passes_through_rock
            point === nothing || (frame["phase_space_point"] = point)
        end
    end
end
