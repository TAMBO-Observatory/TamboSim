"""
TauRunner.jl interface for TAMBO

This module interfaces with the Julia TauRunner.jl package for neutrino propagation
through Earth and local topography.
"""

import TauRunner as TR

# Module-level cached objects
const _tr_earth = Ref{Union{TR.SphericalBody, Nothing}}(nothing)
const _tr_xs = Ref{Union{TR.CrossSections, Nothing}}(nothing)
const _tr_sphere_clp = Ref{Union{TR.SphericalBodyPropagator, Nothing}}(nothing)
const _tr_initialized = Ref(false)

"""
    tr_init()

Initializes the TauRunner.jl library and its components.

This function sets up the Earth model with PREM density profile and
initializes the CSMS cross-sections for neutrino interactions.
The SphericalBodyPropagator is created once and cached for reuse.
"""
function tr_init()
    tables_path = joinpath(get(ENV, "TAMBO_DATA_PATH", tempdir()), "proposal_tables")
    mkpath(tables_path)
    ENV["PROPOSAL_TABLES_PATH"] = tables_path

    # Create Earth with PREM density model
    # Add extra rock layer on top for TAMBO elevation (~3km rock to sea level)
    _tr_earth[] = TR.construct_earth(layers=[(1, 2.6)])

    # Create cross-sections using CSMS model
    _tr_xs[] = TR.CrossSections(TR.CSMS)

    # Create and cache spherical body propagator (expensive — involves PROPOSAL init)
    _tr_sphere_clp[] = TR.SphericalBodyPropagator(_tr_earth[])

    _tr_initialized[] = true
end

"""
    taurunner_interface(particle::Particle, intersections::AbstractVector{Intersection}, seed=nothing) -> Particle

Propagates a particle through a medium using TauRunner.jl.

# Arguments
- `particle::Particle`: The particle to be propagated.
- `intersections::AbstractVector{Intersection}`: A vector of intersections defining the geometry.
- `seed`: An optional seed for the random number generator.

# Returns
- `Particle`: The particle at its final state after propagation.
"""
function taurunner_interface(
    particle::Particle{T},
    intersections::I,
    seed=nothing
)::Particle{T} where {T<:Real, I<:AbstractVector{Intersection{T}}}

    if !_tr_initialized[]
        error("TauRunner not initialized. Call tr_init() first.")
    end

    earth = _tr_earth[]
    xs = _tr_xs[]

    # Set up RNG
    rng = isnothing(seed) ? Random.default_rng() : Random.MersenneTwister(seed)

    # Convert particle to TauRunner format
    # TauRunner uses eV, TamboSim uses GeV with Unitful
    energy_eV = ustrip(particle.energy |> u"eV")
    pdg_id = Int(particle.pdg)
    tr_particle_type = TR.ParticleType(pdg_id)

    if should_go_through_earth(intersections)
        # Earth-skimming case: use spherical Earth model with Chord track
        theta, _ = cart_to_sph(particle.direction)
        track = TR.Chord(theta)

        # Create TauRunner particle
        tr_particle = TR.Particle(tr_particle_type, energy_eV, 0.0, xs)

        # Use cached charged lepton propagator
        clp = _tr_sphere_clp[]

        # Define stopping condition similar to Python version
        stopping_condition = make_stopping_condition()

        # Propagate
        TR.propagate!(tr_particle, track, earth, clp;
                      condition=stopping_condition, rng=rng)

        # Convert back to TamboSim format
        # Calculate position based on track exit
        earth_length = TR.length(earth)
        distance_natural = (TR.x_to_d(track, 1.0) - TR.x_to_d(track, tr_particle.position)) * earth_length
        distance = distance_natural / TR.units.meter * u"m"
        position = distance * reverse(particle.direction) + particle.position

        pdg = ParticleType(Int(tr_particle.id))
        energy = tr_particle.energy / TR.units.GeV * u"GeV"

        return Particle(pdg, energy, position, particle.direction)
    else
        # Local topography case: use layered slab model
        culled_ixs = cull_intersections(intersections)

        if isempty(culled_ixs)
            error("No valid intersections after culling. Input had $(length(intersections)) intersections.")
        end

        total_distance = last(culled_ixs).distance
        layers = Tuple{Float64, Float64}[]

        # Build layer structure from intersections (reverse order - from far to near)
        for intersection in Iterators.rest(reverse(culled_ixs), 2)
            # Determine if this is rock or air based on normal direction
            is_rock = dot(particle.direction, intersection.normal) > 0 ||
                      typeof(intersection) == TamboSim.SphereIntersection{T}
            density = is_rock ? ustrip(u"g/cm^3", ROCK_DENSITY) : ustrip(u"g/cm^3", AIR_DENSITY)

            normalized_boundary = ustrip((total_distance - intersection.distance) / total_distance)

            push!(layers, (density, normalized_boundary))
        end

        # Merge consecutive layers with the same density to avoid confusing
        # TauRunner's C++ code, which can segfault on redundant boundaries
        merged_layers = Tuple{Float64, Float64}[]
        for layer in layers
            if !isempty(merged_layers) && merged_layers[end][1] == layer[1]
                # Same density: extend the previous layer to this boundary
                merged_layers[end] = (layer[1], layer[2])
            else
                push!(merged_layers, layer)
            end
        end
        layers = merged_layers

        # Ensure we have at least one layer ending at 1.0
        rock_ρ = ustrip(u"g/cm^3", ROCK_DENSITY)
        if isempty(layers)
            push!(layers, (rock_ρ, 1.0))
        elseif last(layers)[2] < 1.0
            if last(layers)[1] == rock_ρ
                # Extend existing rock layer to 1.0
                layers[end] = (rock_ρ, 1.0)
            else
                push!(layers, (rock_ρ, 1.0))
            end
        end

        # Create slab body
        total_length_km = ustrip(last(culled_ixs).distance |> u"km")

        # Guard against degenerate geometry that causes segfaults in C++ code
        if total_length_km <= 0.0
            @warn "Degenerate slab length ($total_length_km km), returning null particle"
            return Particle(T)
        end

        # Validate layer boundaries are strictly increasing and in (0, 1]
        for i in 1:length(layers)
            if layers[i][2] <= 0.0 || layers[i][2] > 1.0
                @warn "Invalid layer boundary $(layers[i][2]), returning null particle"
                return Particle(T)
            end
            if i > 1 && layers[i][2] <= layers[i-1][2]
                @warn "Non-increasing layer boundaries, returning null particle"
                return Particle(T)
            end
        end

        body = TR.LayeredConstantSlab(layers, total_length_km)

        track = TR.SlabTrack()
        clp = TR.SlabPropagator(body)
        # Create TauRunner particle
        tr_particle = TR.Particle(tr_particle_type, energy_eV, 0.0, xs)

        # Define stopping condition
        stopping_condition = make_stopping_condition()

        # Propagate
        TR.propagate!(tr_particle, track, body, clp;
                      condition=stopping_condition, rng=rng)

        # NOTE: Propagator caching removed. PROPOSAL C++ propagator objects are
        # bound to a specific geometry (slab body). Reusing them across events with
        # different layer structures causes memory corruption and segfaults.

        # Convert back to TamboSim format
        body_length = TR.length(body)
        distance_natural = TR.x_to_d(track, tr_particle.position) * body_length
        distance = distance_natural / TR.units.meter * u"m"
        position = distance * particle.direction + last(culled_ixs).point

        pdg = ParticleType(Int(tr_particle.id))
        energy = tr_particle.energy / TR.units.GeV * u"GeV"

        return Particle(pdg, energy, position, particle.direction)
    end
end

"""
    make_stopping_condition()

Creates a stopping condition function for TauRunner propagation.

The condition checks if a particle should stop propagating based on:
- For charged leptons (tau): whether remaining distance is less than expected decay range
- For neutrinos: whether interaction depth exceeds remaining column depth
"""
function make_stopping_condition()
    # Physical constants
    c = 299_792_458 * TR.units.meter / TR.units.sec
    tau_lifetime = 2.903e-13 * TR.units.sec
    tau_mass = 1.776 * TR.units.GeV

    function stopping_condition(p, body, track)
        if TR.is_charged_lepton(p.id)
            # For tau: check if decay range exceeds remaining distance
            if abs(Int(p.id)) == 15
                # Decay range estimate with safety factor
                lrange = -(p.energy / tau_mass) * c * tau_lifetime * log(1e-3)
                d = lrange / TR.length(body)
                remaining_distance = TR.x_to_d(track, 1.0 - p.position)
                return d > remaining_distance
            end
            return true  # Other charged leptons: stop
        elseif TR.is_neutrino(p.id)
            # For neutrinos: check if interaction depth exceeds remaining column depth
            remaining_depth = TR.total_column_depth(track, body) - TR.x_to_X(track, body, p.position)
            depth_step = TR.get_total_interaction_depth(p)
            return depth_step * 1e-3 > remaining_depth
        end
        return true
    end
    return stopping_condition
end

"""
    cull_intersections(intersections::AbstractVector{Intersection}) -> Vector{Intersection}

Filters a vector of intersections to remove redundant entries.

This function removes triangle intersections that occur after a sphere intersection,
as they are considered to be inside the Earth and thus irrelevant.

# Arguments
- `intersections::AbstractVector{Intersection}`: The input vector of intersections.

# Returns
- `Vector{Intersection}`: The culled vector of intersections.
"""
function cull_intersections(
    intersections::I,
)::Vector{Intersection{T}} where {T<:Real, I<:AbstractVector{Intersection{T}}}
    include_triangles = true
    culled_intersections = Intersection{T}[]
    for intersection in intersections
        if typeof(intersection) == SphereIntersection{T}
            push!(culled_intersections, intersection)
            include_triangles = false
        elseif include_triangles
            push!(culled_intersections, intersection)
        end
    end
    return culled_intersections
end

"""
    should_go_through_earth(intersections::AbstractVector{Intersection}) -> Bool

Determines if a particle's trajectory passes through the Earth.

This is decided by counting the number of sphere intersections. A count greater than 4
indicates that the particle is passing through the Earth model.

# Arguments
- `intersections::AbstractVector{Intersection}`: The vector of intersections.

# Returns
- `Bool`: `true` if the particle should be propagated through the Earth, `false` otherwise.
"""
function should_go_through_earth(
    intersections::I
)::Bool where {T<:Real, I<:AbstractVector{Intersection{T}}}
    sphere_counter = 0
    for intersection in intersections
        if typeof(intersection) == SphereIntersection{T}
            sphere_counter += 1
        end
    end
    return sphere_counter > 4
end
