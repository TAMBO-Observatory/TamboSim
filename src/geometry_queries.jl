"""
    upwards_ray_at(position::Coordinate{T}) -> Ray{T}
    upwards_ray_at(particle::Particle) -> Ray

Construct a `Ray` originating at `position` and pointing radially outward
from the Earth's center — the local "up" direction at that location.

The direction is computed by normalizing the position vector in
`ecefcoordinates` and converting the resulting unit vector back to
`position`'s coordinate system. Useful as a probe ray for queries like
[`is_above_topography`](@ref).

# Arguments
- `position::Coordinate{T}`: the ray origin.
- `particle::Particle`: convenience overload — uses `particle.position`.

# Returns
- A `Ray{T}` originating at `position` and pointing radially outward.
"""
function upwards_ray_at(position::Coordinate{T}) where {T<:Real}
    d = Direction(
        normalize(convert(ecefcoordinates, position).point),
        ecefcoordinates
    )
    d = convert(position.coordinate_system, d)
    return Ray(position, d)
end
upwards_ray_at(particle::Particle) = upwards_ray_at(particle.position)

"""
    is_above_topography(position::Coordinate, bvh::BVHTree) -> Bool
    is_above_topography(particle::Particle, bvh::BVHTree) -> Bool

Test whether `position` sits above all triangles in `bvh`. Returns `true`
if a ray shot radially outward from `position` (see [`upwards_ray_at`](@ref))
misses every triangle in the tree.

Used to distinguish particles in air (above topography) from particles
inside rock (below) — e.g. when filtering tau decays by their decay
medium, or when checking whether a propagated lepton ranged out inside
the mountain.

# Arguments
- `position::Coordinate`: the location to query.
- `particle::Particle`: convenience overload — uses `particle.position`.
- `bvh::BVHTree`: BVH over topography triangles (typically `gframe["bvh"]`).

# Returns
- `true` if the upwards ray from `position` does not intersect `bvh`.
"""
function is_above_topography(position::Coordinate, bvh::BVHTree)
    return isempty(intersect_all(bvh, upwards_ray_at(position)))
end
is_above_topography(particle::Particle, bvh::BVHTree) =
    is_above_topography(particle.position, bvh)
