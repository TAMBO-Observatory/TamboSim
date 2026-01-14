"""
    Plane{T}

Represents an infinite plane in 3D space, defined by a point on the plane and a normal vector.

All `Coordinate` and `Direction` objects used to define the plane must belong to the
same `CoordinateSystem`.

# Fields
- `point::Coordinate{T}`: A `Coordinate` object representing a point on the plane.
- `normal::Direction{T}`: A `Direction` object representing the normal vector to the plane.

# Constructors
- `Plane(point::Coordinate{T}, normal::Direction{T})`: Primary constructor that asserts
  the `point` and `normal` share the same coordinate system.
"""
struct Plane{T}
    point::Coordinate{T}
    normal::Direction{T}
    function Plane(point::Coordinate{T}, normal::Direction{T}) where T
        @assert CoordinateSystem(point)==CoordinateSystem(point)
        return new{T}(point, normal)
    end
end

"""
    Base.convert(target_cs::CoordinateSystem{T}, plane::Plane{T}) -> Plane{T}

Converts a `Plane` object from its current coordinate system to a `target_cs`.

This function converts both the `point` and `normal` components of the plane
to the `target_cs` and returns a new `Plane` object.

# Arguments
- `target_cs::CoordinateSystem{T}`: The target coordinate system.
- `plane::Plane{T}`: The `Plane` object to convert.

# Returns
- A new `Plane` object in the `target_cs`.
"""
function Base.convert(cs::CoordinateSystem{T}, plane::Plane{T}) where {T<:Real}
    if CoordinateSystem(plane.point)==cs
        return plane
    end
    return Plane(convert(cs, plane.point), convert(cs, plane.normal))
end
