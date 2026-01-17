"""
    Triangle{T<:Real}

Represents a triangle in 3D space, defined by three `Coordinate` vertices.

All vertices (`v1`, `v2`, `v3`) are expected to belong to the same `CoordinateSystem`.
The order of vertices can imply the normal direction.

# Fields
- `v1::Coordinate{T}`: The first vertex of the triangle.
- `v2::Coordinate{T}`: The second vertex of the triangle.
- `v3::Coordinate{T}`: The third vertex of the triangle.
"""
struct Triangle{T <: Real}
    v1::Coordinate{T}
    v2::Coordinate{T}
    v3::Coordinate{T}
end

"""
    Triangle(v1::Coordinate{T}, v2::Coordinate{T}, v3::Coordinate{T}, ref::Coordinate{T}) -> Triangle

Constructs a `Triangle` and potentially reorients its vertices based on a reference point.

This constructor calculates the normal of the triangle and checks its orientation relative
to a `ref`erence `Coordinate`. If the dot product of the normal with the reference coordinate
is positive, it reverses the winding order of the vertices (by swapping `v2` and `v3`)
to ensure a consistent outward-pointing normal relative to `ref`.

# Arguments
- `v1::Coordinate{T}`: The first vertex.
- `v2::Coordinate{T}`: The second vertex.
- `v3::Coordinate{T}`: The third vertex.
- `ref::Coordinate{T}`: A reference `Coordinate` used to determine the desired normal orientation.

# Returns
- A `Triangle` object, potentially with reordered vertices.
"""
function Triangle(
    v1::Coordinate{T},
    v2::Coordinate{T},
    v3::Coordinate{T},
    ref::Coordinate{T}
) where {T}
    n = normal(v1, v2, v3)
    d = dot(n, ref)
    if d > 0 * d
        v2, v3 = v3, v2
    end
    return Triangle(v1, v2, v3)
end

"""
    CoordinateSystem(t::Triangle) -> CoordinateSystem

Retrieves the `CoordinateSystem` of a `Triangle`.

This function returns the coordinate system of the first vertex (`v1`), assuming
all vertices of the triangle belong to the same coordinate system.

# Arguments
- `t::Triangle`: The `Triangle` object.

# Returns
- The `CoordinateSystem` of the triangle.
"""
function CoordinateSystem(t::Triangle)
    return CoordinateSystem(t.v1)
end

"""
    Base.iterate(triangle::Triangle, state=1)

Enables iteration over the vertices of a `Triangle` object.

This allows a `Triangle` to be used in loops (e.g., `for v in my_triangle`).
It yields the vertices `v1`, `v2`, and `v3` in order.
"""
function Base.iterate(triangle::Triangle, state=1)
    if state==1
        return (triangle.v1, 2)
    elseif state==2
        return (triangle.v2, 3)
    elseif state==3
        return (triangle.v3, 4)
    else
        return nothing
    end
end

"""
    Base.length(triangle::Triangle) -> Int

Returns the number of vertices in a `Triangle` (always 3).
"""
function Base.length(triangle::Triangle)
    return 3
end

"""
    Sphere{T<:Real}

Represents a sphere in 3D space, defined by its center `Coordinate` and `radius`.

# Fields
- `center::Coordinate{T}`: The `Coordinate` of the sphere's center.
- `radius::Quantity{T, ldim, typeof(u"m")}`: The radius of the sphere, with units of length.
"""
struct Sphere{T <: Real}
    center::Coordinate{T}
    radius::Quantity{T, ldim, typeof(u"m")}
end

"""
    CoordinateSystem(sphere::Sphere) -> CoordinateSystem

Retrieves the `CoordinateSystem` of a `Sphere`.

This function returns the coordinate system of the sphere's `center`.

# Arguments
- `sphere::Sphere`: The `Sphere` object.

# Returns
- The `CoordinateSystem` of the sphere.
"""
function CoordinateSystem(sphere::Sphere)
    return CoordinateSystem(sphere.center)
end
