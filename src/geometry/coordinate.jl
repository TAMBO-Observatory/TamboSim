"""
    Coordinate{T<:Real}

Represents a point in 3D space relative to a specific `CoordinateSystem`.

# Fields
- `point::SVector{3, Quantity{T,ldim,typeof(u"m")}}`: The SVector representing the point's coordinates (x, y, z) with units of meters.
- `coordinate_system::CoordinateSystem{T}`: The coordinate system in which this point is defined.

# Constructors
- `Coordinate(point::AbstractVector{<:Quantity}, cs::CoordinateSystem)`: Creates a `Coordinate` from a vector of quantities and a coordinate system.
"""
struct Coordinate{T <: Real}
    point::SVector{3, Quantity{T,ldim,typeof(u"m")}}
    coordinate_system::CoordinateSystem{T}
    function Coordinate(point::AbstractVector{<:Quantity}, cs::CoordinateSystem)
        point_sv = SVector{3}(point)
        T = promote_type(eltype(cs), eltype(one(point_sv.x)))
        new{T}(point_sv, cs)
    end
end

"""
    Coordinate(x, y, z, cs::CoordinateSystem) -> Coordinate

Constructs a `Coordinate` object from individual x, y, z components and a `CoordinateSystem`.

This is a convenience constructor that wraps the x, y, z values into a vector and calls
the primary `Coordinate` constructor.

# Arguments
- `x`: The x-component of the point.
- `y`: The y-component of the point.
- `z`: The z-component of the point.
- `cs::CoordinateSystem`: The coordinate system for this point.

# Returns
- A `Coordinate` object.
"""
function Coordinate(x, y, z, cs::CoordinateSystem)
    return Coordinate([x, y, z], cs)
end

"""
    CoordinateSystem(c::Coordinate) -> CoordinateSystem

Retrieves the `CoordinateSystem` associated with a given `Coordinate` object.

# Arguments
- `c::Coordinate`: The `Coordinate` object.

# Returns
- The `CoordinateSystem` of the given coordinate.
"""
function CoordinateSystem(c::Coordinate)
    return c.coordinate_system
end

"""
    Base.eltype(c::Coordinate)

Returns the element type of the `Coordinate`, which is typically the element type of its underlying coordinate system.
"""
Base.eltype(c::Coordinate) = eltype(c.coordinate_system)
"""
    Base.size(c::Coordinate)
    Base.length(c::Coordinate)
    Base.getindex(c::Coordinate, i)
    Base.iterate(c::Coordinate, state=1)

These methods allow a `Coordinate` object to behave like a 3-element `SVector` (or array)
for iteration and indexed access of its `x, y, z` components.
"""
Base.size(c::Coordinate) = (3,)
Base.length(c::Coordinate) = 3
Base.getindex(c::Coordinate, i) = c.point[i]
function Base.iterate(c::Coordinate, state=1)
    state > length(c) && return nothing
    return (c.point[state], state + 1)
end

"""
    Base.:+(a::Coordinate, b::Coordinate) -> Coordinate

Adds two `Coordinate` objects.

Both coordinates must be defined in the same `CoordinateSystem`. The operation performs
vector addition on their underlying `point` SVectors.

# Arguments
- `a::Coordinate`: The first `Coordinate`.
- `b::Coordinate`: The second `Coordinate`.

# Returns
- A new `Coordinate` object representing the sum.
"""
function Base.:+(a::Coordinate, b::Coordinate)
    check_coordinate_systems(a, b)
    return Coordinate(a.point + b.point, a.coordinate_system)
end

"""
    Base.:-(a::Coordinate, b::Coordinate) -> Coordinate

Subtracts one `Coordinate` object from another.

Both coordinates must be defined in the same `CoordinateSystem`. The operation performs
vector subtraction on their underlying `point` SVectors.

# Arguments
- `a::Coordinate`: The `Coordinate` to subtract from.
- `b::Coordinate`: The `Coordinate` to subtract.

# Returns
- A new `Coordinate` object representing the difference.
"""
function Base.:-(a::Coordinate, b::Coordinate)
    check_coordinate_systems(a, b)
    return Coordinate(a.point - b.point, a.coordinate_system)
end

"""
    Base.Broadcast.broadcastable(coord::Coordinate)

Enables `Coordinate` objects to participate in Julia's broadcasting mechanism.

This makes a `Coordinate` object broadcast as a "scalar" when mixed with arrays.
"""
Base.Broadcast.broadcastable(coord::Coordinate) = (coord,)

# Generic function to handle both min and max
"""
    coordinate_extremum(f::Function, coords::Coordinate...) -> Coordinate

Finds the element-wise extremum (e.g., minimum or maximum) among a set of `Coordinate` objects.

This internal helper function applies a given function `f` (e.g., `minimum` or `maximum`)
to each component (x, y, z) across all provided `coords`. All input coordinates
are expected to be in the same `CoordinateSystem`.

# Arguments
- `f::Function`: The aggregation function (e.g., `minimum`, `maximum`).
- `coords::Coordinate...`: One or more `Coordinate` objects.

# Returns
- A new `Coordinate` object where each component is the extremum of the corresponding
  components from the input coordinates.
"""
function coordinate_extremum(f::Function, coords::Coordinate...)
    cs = first(coords).coordinate_system
    #for coord in coords
    #    coord.coordinate_system == cs || error("Coordinate systems must match")
    #end

    x = f(map(x->x.point[1], coords))
    y = f(map(x->x.point[2], coords))
    z = f(map(x->x.point[3], coords))
    result_point = SVector{3}(x,y,z)

    return Coordinate(result_point, cs)
end

# Define broadcasted for max
"""
    Base.broadcasted(::typeof(max), coords::Coordinate...) -> Coordinate

Performs element-wise maximum operation on multiple `Coordinate` objects.

# Arguments
- `coords::Coordinate...`: One or more `Coordinate` objects.

# Returns
- A new `Coordinate` object with the maximum components.
"""
function Base.broadcasted(::typeof(max), coords::Coordinate...)
    return coordinate_extremum(maximum, coords...)
end

# Define broadcasted for min
"""
    Base.broadcasted(::typeof(min), coords::Coordinate...) -> Coordinate

Performs element-wise minimum operation on multiple `Coordinate` objects.

# Arguments
- `coords::Coordinate...`: One or more `Coordinate` objects.

# Returns
- A new `Coordinate` object with the minimum components.
"""
function Base.broadcasted(::typeof(min), coords::Coordinate...)
    return coordinate_extremum(minimum, coords...)
end

"""
    Base.:*(a::Coordinate, s::Number) -> Coordinate

Scales a `Coordinate` object by a scalar `s`.

# Arguments
- `a::Coordinate`: The `Coordinate` object.
- `s::Number`: The scalar value.

# Returns
- A new `Coordinate` object with its components scaled by `s`.
"""
Base.:*(a::Coordinate, s::Number) = Coordinate(a.point * s, a.coordinate_system)
"""
    Base.:/(a::Coordinate, s::Number) -> Coordinate

Divides a `Coordinate` object by a scalar `s`.

# Arguments
- `a::Coordinate`: The `Coordinate` object.
- `s::Number`: The scalar value.

# Returns
- A new `Coordinate` object with its components divided by `s`.
"""
Base.:/(a::Coordinate, s::Number) = Coordinate(a.point / s, a.coordinate_system)
"""
    Base.:*(s::Number, a::Coordinate) -> Coordinate

Scales a `Coordinate` object by a scalar `s` (scalar-first multiplication).

# Arguments
- `s::Number`: The scalar value.
- `a::Coordinate`: The `Coordinate` object.

# Returns
- A new `Coordinate` object with its components scaled by `s`.
"""
Base.:*(s::Number, a::Coordinate) = Coordinate(s * a.point, a.coordinate_system)
"""
    LinearAlgebra.normalize(c::Coordinate) -> SVector

Normalizes the `point` vector of a `Coordinate` object.

Note that this function returns an `SVector` representing the normalized direction
and not a `Coordinate` object.

# Arguments
- `c::Coordinate`: The `Coordinate` object to normalize.

# Returns
- An `SVector` representing the normalized direction.
"""
LinearAlgebra.normalize(c::Coordinate) = normalize(c.point)

"""
    Base.convert(target_cs::CoordinateSystem, coord::Coordinate) -> Coordinate

Converts a `Coordinate` object from its current coordinate system to a `target_cs`.

This function applies the necessary inverse transformations to move the point from
its original system to a global reference, and then applies the transformations
to place it in the `target_cs`.

# Arguments
- `target_cs::CoordinateSystem`: The target coordinate system.
- `coord::Coordinate`: The `Coordinate` object to convert.

# Returns
- A new `Coordinate` object in the `target_cs`.
"""
function Base.convert(coordinate_system::CoordinateSystem, coord::Coordinate)
    if coordinate_system==coord.coordinate_system
        return coord
    end
    r1 = LinearMap(RotMatrix(coord.coordinate_system.rotation))
    t1 = Translation(coord.coordinate_system.origin)
    r2 = LinearMap(RotMatrix(coordinate_system.rotation))
    t2 = Translation(coordinate_system.origin)
    point = inv(r1)(coord.point)
    point = t1(point)
    point = inv(t2)(point)
    point = r2(point)

    return Coordinate(point, coordinate_system)
end
