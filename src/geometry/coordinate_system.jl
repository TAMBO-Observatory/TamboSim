# Coordinate system
"""
    CoordinateSystem{T<:Real}

Represents a 3D Cartesian coordinate system defined by an origin and a rotation.

# Fields
- `origin::SVector{3, Quantity{T,ldim,typeof(u"m")}}`: The origin of the coordinate system.
- `rotation::SMatrix{3, 3, T, 9}`: A 3x3 rotation matrix that transforms coordinates from this system to a reference system (e.g., ECEF).
"""
struct CoordinateSystem{T<:Real}
    origin::SVector{3, Quantity{T,ldim,typeof(u"m")}}
    rotation::SMatrix{3, 3, T, 9}
end

"""
    CoordinateSystem(longlat::Tuple{Float64, Float64}, rearth::Quantity)

Creates a local `CoordinateSystem` centered at a specific longitude and latitude on a spherical Earth.

The origin is set to the Cartesian coordinates corresponding to the given longitude and
latitude, and the rotation is calculated to align the z-axis with the local zenith.

# Arguments
- `longlat::Tuple{Float64, Float64}`: A tuple containing the longitude and latitude in degrees.
- `rearth::Quantity`: The radius of the Earth.

# Returns
- A new `CoordinateSystem` object.
"""
function CoordinateSystem(longlat::NTuple{2,<:Real}, rearth::Quantity)
    origin = SVector{3}(longlat_to_cart(longlat...) * rearth)
    rotation = compute_rotation(longlat)
    return CoordinateSystem(origin, rotation)
end

"""
    Base.eltype(cs::CoordinateSystem)

Returns the element type of the `CoordinateSystem`, which is typically the element type of its rotation matrix.

# Arguments
- `cs::CoordinateSystem`: The `CoordinateSystem` object.

# Returns
- The element type.
"""
Base.eltype(cs::CoordinateSystem) = eltype(cs.rotation)

"""
    ecefcoordinates

Canonical Earth-Centered, Earth-Fixed `CoordinateSystem`: origin at `(0, 0, 0)` m
with the identity rotation. Serves as the global reference frame to which all
other `CoordinateSystem`s are ultimately resolved.

Element type is `Float64`; because every coordinate transform chains back to this
constant, sub-`Float64` precision is not achievable end-to-end.
"""
const ecefcoordinates = CoordinateSystem(
    SVector{3}([0.0*u"m", 0.0*u"m", 0.0*u"m"]),
    SMatrix{3, 3, Float64, 9}([1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0])
)
