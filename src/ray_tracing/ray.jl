"""
    Ray{T<:Real}

Represents a ray in 3D space, defined by an origin `Coordinate` and a `Direction`.

The origin and direction must belong to the same `CoordinateSystem`.

# Fields
- `origin::Coordinate{T}`: The starting point of the ray.
- `direction::Direction{T}`: The direction vector of the ray.

# Constructors
- `Ray(origin::Coordinate{T}, direction::Direction{T})`: Primary constructor that asserts
  the `origin` and `direction` share the same coordinate system.
"""
struct Ray{T<:Real}
    origin::Coordinate{T}
    direction::Direction{T}

    function Ray(origin::Coordinate{T}, direction::Direction{T}) where {T<:Real}
        origin.coordinate_system==direction.coordinate_system || throw("Coordinate system mismatch")
        new{T}(origin, direction)
    end
end

"""
    Base.reverse(ray::Ray) -> Ray

Returns a new `Ray` object with the same origin but with its direction reversed.

# Arguments
- `ray::Ray`: The `Ray` object to reverse.

# Returns
- A new `Ray` object with the direction reversed.
"""
Base.reverse(ray::Ray) = Ray(ray.origin, reverse(ray.direction))
