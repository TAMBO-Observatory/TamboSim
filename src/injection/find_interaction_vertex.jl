AIR_DENSITY = 1.205e-3 * u"g"/u"cm"^3
ROCK_DENSITY = 2.65 * u"g"/u"cm"^3

"""
    find_vertex_distance_by_distance(
        direction::Direction{T},
        distance::Quantity{T},
        intersections::AbstractVector{Intersection{T}},
        epsilon::Float64=1e-3
    ) -> Tuple{Quantity{T}, Quantity{T}, Quantity{T}}

Finds a random interaction vertex along a given `direction` up to a specified `distance`,
considering varying material densities from `intersections`.

This function simulates a particle traveling through different media layers (defined by `intersections`).
It calculates the total column depth encountered and then randomly selects an interaction point
based on that column depth.

# Arguments
- `direction::Direction{T}`: The direction of particle travel.
- `distance::Quantity{T}`: The maximum physical distance to consider for interaction.
- `intersections::AbstractVector{Intersection{T}}`: A sorted list of `Intersection` objects
  defining the boundaries of different material layers.
- `epsilon::Float64`: A small value used for numerical stability (default: 1e-3, though not explicitly used in the provided code snippet).

# Returns
- `Tuple{Quantity{T}, Quantity{T}, Quantity{T}}`: A tuple containing:
    - The physical distance to the interaction vertex.
    - The total column depth traversed up to that vertex.
    - The density of the material at the interaction vertex.
"""
function find_vertex_distance_by_distance(
    direction::Direction{T},
    distance::Quantity{T},
    intersections::I,
    epsilon::Float64=1e-3
) where {T<:Real, I<:AbstractVector{Intersection{T}}}

    densities = @views compute_density(intersections, direction)[2:end]
    distances = @views compute_lengths(intersections)[2:end]
    @assert length(densities)==length(distances)
    #@show densities
    column_depth = 0.0u"g/cm^2"
    d, cd = 0.0u"m", 0.0u"g/cm^2"
    for (dist, dens) in zip(distances, densities)
        if d + dist > distance
            cd += (distance - d) * dens
            break
        end
        cd += dist * dens
        d += dist
    end

    target_column_depth = rand(Uniform(0, ustrip(cd |> u"g/cm^2"))) * u"g/cm^2"
    accrued_cd = 0.0u"g/cm^2"
    accrued_d = 0u"m"
    for (dist, dens) in zip(distances, densities)
        segment_cd = dist * dens
        if segment_cd + accrued_cd > target_column_depth
            accrued_d += (target_column_depth - accrued_cd) / dens
            if dens < 1u"g/cm^3"
                println("Expect air")
            end
            return accrued_d, cd, dens
        end
        accrued_d += dist
        accrued_cd += segment_cd
    end
    # Fallback: return final position if loop completes (edge case)
    return accrued_d, cd, last(densities)
end

"""
    find_vertex_distance_by_cd(
        direction::Direction{T},
        cd::Quantity{T},
        intersections::AbstractVector{Intersection{T}},
        epsilon::Float64=1e-3
    ) -> Tuple{Quantity{T}, Quantity{T}, Quantity{T}}

Finds a random interaction vertex along a given `direction` up to a specified `column_depth`,
considering varying material densities from `intersections`.

This function simulates a particle traveling through different media layers (defined by `intersections`).
It calculates the available column depth and then randomly selects an interaction point
based on the specified and available column depth.

# Arguments
- `direction::Direction{T}`: The direction of particle travel.
- `cd::Quantity{T}`: The maximum column depth (e.g., in g/cm^2) to consider for interaction.
- `intersections::AbstractVector{Intersection{T}}`: A sorted list of `Intersection` objects
  defining the boundaries of different material layers.
- `epsilon::Float64`: A small value used for numerical stability (default: 1e-3, though not explicitly used in the provided code snippet).

# Returns
- `Tuple{Quantity{T}, Quantity{T}, Quantity{T}}`: A tuple containing:
    - The physical distance to the interaction vertex.
    - The total column depth traversed up to that vertex.
    - The density of the material at the interaction vertex.
"""
function find_vertex_distance_by_cd(
    direction::Direction{T},
    cd::Quantity{T},
    intersections::I,
    epsilon::Float64=1e-3
) where {T<:Real, I<:AbstractVector{Intersection{T}}}

    
    densities = @views compute_density(intersections, direction)[2:end]
    distances = @views compute_lengths(intersections)[2:end]
    
    available_cd = sum([dist*dens for (dist, dens) in zip(distances, densities)])
    if available_cd < cd
        cd = available_cd
    end

    target_column_depth = rand(Uniform(0, ustrip(cd |> u"g/cm^2"))) * u"g/cm^2"
    accrued_cd = 0.0u"g/cm^2"
    accrued_d = 0u"m"
    for (dist, dens) in zip(distances, densities)
        segment_cd = dist * dens
        if segment_cd + accrued_cd > target_column_depth
            accrued_d += (target_column_depth - accrued_cd) / dens
            if dens < 1u"g/cm^3"
                println("Expect air")
            end
            return accrued_d, cd, dens
        end
        accrued_d += dist
        accrued_cd += segment_cd
    end
    # Fallback: return final position if loop completes (edge case)
    return accrued_d, cd, last(densities)
end

"""
    compute_density(ixs::AbstractVector{Intersection{T}}, d::Direction{T}) -> Vector{Quantity{T, mdim/ldim^3}}

Computes the material density for each segment defined by a sequence of intersections.

For `TriangleIntersection`s, the density (air or rock) is determined by whether the
triangle's normal faces towards or away from the given `direction`. For `SphereIntersection`s,
the density is assumed to be `ROCK_DENSITY`.

# Arguments
- `ixs::AbstractVector{Intersection{T}}`: A sorted list of `Intersection` objects, defining
  the points where a ray crosses material boundaries.
- `d::Direction{T}`: The direction of the ray's travel.

# Returns
- `Vector{Quantity{T, mdim/ldim^3}}`: A vector of densities for each segment between intersections.
"""
function compute_density(
    ixs::I,
    d::Direction{T}
) where {T<:Real,I<:AbstractVector{Intersection{T}}}
    densities = Vector{Quantity{T, mdim/ldim^3}}(undef, length(ixs))
    for (idx, ix) in enumerate(ixs)
        if typeof(ix)==TriangleIntersection{T}
            b = dot(d, ix.normal) < 0
            density = b ? AIR_DENSITY : ROCK_DENSITY
            densities[idx] = density
        elseif typeof(ix)==SphereIntersection{T}
            # This is not totally true, but I think it should be okay
            density = ROCK_DENSITY
            densities[idx] = density
        end
    end
    return densities
end

"""
    compute_lengths(ixs::AbstractVector{Intersection{T}}) -> Vector{Quantity{T,ldim,typeof(u"m")}}

Computes the physical length of each segment between a sequence of intersections.

Assuming `ixs` is sorted by `distance`, this function calculates the length of
each path segment from the previous intersection point to the current one.

# Arguments
- `ixs::AbstractVector{Intersection{T}}`: A sorted list of `Intersection` objects,
  where each intersection has a `distance` field.

# Returns
- `Vector{Quantity{T,ldim,typeof(u"m")}}`: A vector of lengths for each segment.
"""
function compute_lengths(
    ixs::I
) where {T<:Real, I<:AbstractVector{Intersection{T}}}
    prv, lengths = 0.0u"m", Vector{Quantity{T,ldim,typeof(u"m")}}(undef, length(ixs))
    for (idx, ix) in enumerate(ixs)
        lengths[idx] = ix.distance - prv
        prv = ix.distance
    end
    return lengths
end
        
