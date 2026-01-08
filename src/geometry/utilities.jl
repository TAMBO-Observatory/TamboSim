"""
    centroid(triangle::Triangle) -> Coordinate

Calculates the centroid (geometric center) of a `Triangle`.

The centroid is the average of the three vertices of the triangle.

# Arguments
- `triangle::Triangle`: The `Triangle` object.

# Returns
- A `Coordinate` object representing the centroid of the triangle.
"""
function centroid(triangle::T) where {T<:Triangle}
    p = triangle.v1 + triangle.v2 + triangle.v3
    return p / 3
end

"""
    check_coordinate_systems(coord1::Coordinate, coord2::Coordinate)

Asserts that two `Coordinate` objects belong to the same `CoordinateSystem`.

This function is typically used internally to ensure consistency before performing
operations on coordinates. It will throw an `AssertionError` if the coordinate systems differ.

# Arguments
- `coord1::Coordinate`: The first `Coordinate`.
- `coord2::Coordinate`: The second `Coordinate`.
"""
function check_coordinate_systems(coord1::Coordinate, coord2::Coordinate)
    @assert coord1.coordinate_system==coord2.coordinate_system "Incompatible coordinate systems"
end

"""
    compute_rotation(longlat::Tuple{Float64, Float64}) -> SMatrix{3, 3, Float64, 9}

Computes a rotation matrix from ECEF coordinates to a local East-North-Up (ENU) system.

The rotation matrix is calculated based on the given longitude and latitude.

# Arguments
- `longlat::Tuple{Float64, Float64}`: A tuple containing the longitude and latitude in radians.

# Returns
- An `SMatrix{3, 3, Float64, 9}` representing the rotation matrix.
"""
function compute_rotation(longlat)
    # Rotation matrix components
    long, lat = longlat
    sin_lat, cos_lat = sin(lat), cos(lat)
    sin_long, cos_long = sin(long), cos(long)

    # Rotation matrix from ECEF to local ENU (East, North, Up)
    R = SMatrix{3, 3}([
        -sin_long           cos_long           0.0
        -sin_lat * cos_long -sin_lat * sin_long cos_lat
         cos_lat * cos_long  cos_lat * sin_long sin_lat
    ])
    return R
end

"""
    longlat_to_cart(long::Real, lat::Real) -> Vector{Float64}

Converts longitude and latitude coordinates to Cartesian (x, y, z) coordinates on a unit sphere.

# Arguments
- `long::Real`: Longitude in radians.
- `lat::Real`: Latitude in radians.

# Returns
- A `Vector{Float64}` of length 3, representing the x, y, and z Cartesian coordinates.
"""
function longlat_to_cart(long, lat)
    return [cos(long) * cos(lat), sin(long) * cos(lat), sin(lat)]
end

"""
    cart_to_longlat(x::Real, y::Real, z::Real) -> Vector{Float64}

Converts Cartesian (x, y, z) coordinates (assumed to be on a sphere) to longitude and latitude.

The input vector is first normalized.

# Arguments
- `x::Real`, `y::Real`, `z::Real`: The Cartesian coordinates.

# Returns
- A `Vector{Float64}` of length 2, `[longitude, latitude]` in radians.
"""
function cart_to_longlat(x, y, z)
    n = norm([x, y, z])
    x, y, z = [x, y, z] ./ n
    return [atan(y, x), asin(z)]
end

"""
    cart_to_longlat(c::Coordinate) -> Vector{Float64}

Converts a `Coordinate` object to longitude and latitude.

The `Coordinate` is first converted to the `ecefcoordinates` system before
performing the conversion.

# Arguments
- `c::Coordinate`: The `Coordinate` object.

# Returns
- A `Vector{Float64}` of length 2, `[longitude, latitude]` in radians.
"""
function cart_to_longlat(c::Coordinate)
    c = convert(ecefcoordinates, c)
    cart_to_longlat(c.point...)
end

"""
    sph_to_cart(theta::Real, phi::Real) -> Vector{Float64}

Converts spherical coordinates (theta, phi) to Cartesian (x, y, z) coordinates on a unit sphere.

# Arguments
- `theta::Real`: Polar angle (inclination) in radians.
- `phi::Real`: Azimuthal angle in radians.

# Returns
- A `Vector{Float64}` of length 3, representing the x, y, and z Cartesian coordinates.
"""
function sph_to_cart(theta, phi)
    return [cos(phi) * sin(theta), sin(theta) * sin(phi), cos(theta)]
end

"""
    cart_to_sph(d::Direction) -> Tuple{Float64, Float64}

Converts a `Direction` object's Cartesian components to spherical coordinates (theta, phi).

# Arguments
- `d::Direction`: The `Direction` object.

# Returns
- A `Tuple{Float64, Float64}`: `(theta, phi)` in radians.
"""
function cart_to_sph(d::Direction)
    return acos(d.point.z), atan(d.point.y, d.point.x)
end

"""
    normal(v1::AbstractVector, v2::AbstractVector, v3::AbstractVector) -> Vector{Float64}

Calculates the normalized normal vector of a triangle defined by three abstract vectors.

The normal vector is computed as the normalized cross product of two edges of the triangle.
Input vectors are expected to be 3-dimensional.

# Arguments
- `v1::AbstractVector`, `v2::AbstractVector`, `v3::AbstractVector`: The three vertices of the triangle.

# Returns
- A `Vector{Float64}` representing the normalized normal vector.
"""
function normal(v1::AbstractVector, v2::AbstractVector, v3::AbstractVector)
    (length(v1)==3 && length(v3)==3 && length(v3)==3) || throw("Can't take cross product")
    edge1 = v1 - v2
    edge2 = v1 - v3
    n = cross(edge1, edge2)
    n /= norm(n)

end

"""
    normal(v1::Coordinate{T}, v2::Coordinate{T}, v3::Coordinate{T}) -> Direction{T}

Calculates the normalized normal `Direction` of a triangle defined by three `Coordinate` objects.

All three coordinates must belong to the same `CoordinateSystem`. The normal is computed
as the normalized cross product of two edges.

# Arguments
- `v1::Coordinate{T}`, `v2::Coordinate{T}`, `v3::Coordinate{T}`: The three vertices of the triangle.

# Returns
- A `Direction{T}` object representing the normalized normal vector.
"""
function normal(v1::Coordinate{T}, v2::Coordinate{T}, v3::Coordinate{T}) where {T<:Real}
    CoordinateSystem(v1)==CoordinateSystem(v2)==CoordinateSystem(v3) || throw("incompatible coordinate systems")
    edge1 = v1.point - v2.point
    edge2 = v1.point - v3.point
    n = cross(edge1, edge2)
    n /= norm(n)
    return Direction(n, CoordinateSystem(v1))
end

"""
    normal(triangle::Triangle{T}) -> Direction{T}

Calculates the normalized normal `Direction` of a `Triangle` object.

This is a convenience method that calls `normal(v1, v2, v3)` with the triangle's vertices.

# Arguments
- `triangle::Triangle{T}`: The `Triangle` object.

# Returns
- A `Direction{T}` object representing the normalized normal vector.
"""
function normal(triangle::Triangle{T}) where {T<:Real}
    return normal(triangle.v1, triangle.v2, triangle.v3)
end

"""
    area(triangle::Triangle{T}) -> Quantity{T,ldim^2,typeof(u"m^2")}

Calculates the surface area of a `Triangle`.

The area is computed as half the magnitude of the cross product of two of its edge vectors.

# Arguments
- `triangle::Triangle{T}`: The `Triangle` object.

# Returns
- A `Quantity` representing the area of the triangle, with units of square meters.
"""
function area(triangle::Triangle{T})::Quantity{T,ldim^2,typeof(u"m^2")} where {T<:Real}
    a = triangle.v2.point - triangle.v1.point
    b = triangle.v3.point - triangle.v1.point

    cross_product = cross(a, b)

    return 0.5 * norm(cross_product)
end

"""
    validate_triangle(triangle::Triangle{T}, center::Coordinate{T}) -> Bool

Validates the orientation of a `Triangle` relative to a central `Coordinate`.

This function checks if the normal vector of the triangle points generally
outwards from a given `center` point. It's used to ensure triangles in a mesh
have a consistent outward-pointing normal.

# Arguments
- `triangle::Triangle{T}`: The `Triangle` object to validate.
- `center::Coordinate{T}`: A central `Coordinate` used as a reference for "outward".

# Returns
- `Bool`: `true` if the triangle's normal points away from the `center`, `false` otherwise.
"""
function validate_triangle(triangle::Triangle{T}, center::Coordinate{T}) where {T<:Real}
    cent = centroid(triangle)
    n1 = normal(triangle)
    n2 = normalize(cent.point - center.point)
    return dot(n1.point, n2) > 0
end

"""
    StatsBase.sample(t::Triangle) -> Coordinate

Randomly samples a point uniformly distributed within a `Triangle`.

This function uses barycentric coordinates to generate a random point inside the triangle.

# Arguments
- `t::Triangle`: The `Triangle` object to sample from.

# Returns
- A `Coordinate` object representing a random point within the triangle.
"""
function StatsBase.sample(t::Triangle)
    r1 = rand()
    r2 = rand()

    if r1 + r2 > 1
        r1 = 1 - r1
        r2 = 1 - r2
    end

    return (1 - r1 - r2) * t.v1 + r1 * t.v2 + r2 * t.v3
end
