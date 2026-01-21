"""
    Direction{T<:Real}

Represents a normalized 3D direction vector within a specific `CoordinateSystem`.

The `point` field stores a normalized `SVector{3}`. When constructing a `Direction`
object, the input vector is automatically normalized.

# Fields
- `point::SVector{3,T}`: The normalized SVector representing the direction (x, y, z).
- `coordinate_system::CoordinateSystem{T}`: The coordinate system in which this direction is defined.

# Constructors
- `Direction(point::AbstractVector, coordinate_system::CoordinateSystem)`: Creates a `Direction` from an abstract vector and a coordinate system. The vector is normalized.
"""
struct Direction{T<:Real}
    point::SVector{3,T}
    coordinate_system::CoordinateSystem{T}
    function Direction(point::AbstractVector, coordinate_system::CoordinateSystem)
        point_sv = SVector{3}(point)
        point_norm = normalize(point_sv)
        T = eltype(point_norm)
        return new{T}(point_norm, coordinate_system)
    end
end

"""
    Direction(point::Vector, coordinate_system::CoordinateSystem) -> Direction

Constructs a `Direction` object from a standard Julia `Vector` and a `CoordinateSystem`.

This is a convenience constructor that asserts the input vector has 3 elements
and then converts it to an `SVector` before calling the primary `Direction` constructor.

# Arguments
- `point::Vector`: A 3-element `Vector` representing the direction components.
- `coordinate_system::CoordinateSystem`: The coordinate system for this direction.

# Returns
- A `Direction` object.
"""
function Direction(point::Vector, coordinate_system::CoordinateSystem)
    @assert length(point)==3
    return Direction(SVector{3}(point), coordinate_system)
end

"""
    Base.size(d::Direction)
    Base.length(d::Direction)
    Base.getindex(d::Direction, i)

These methods allow a `Direction` object to behave like a 3-element `SVector` (or array)
for iteration and indexed access of its `x, y, z` components.
"""
Base.size(d::Direction) = (3,)
Base.length(d::Direction) = 3
Base.getindex(d::Direction, i) = d.point[i]

"""
    CoordinateSystem(d::Direction)

Returns the coordinate system associated with a Direction object.
"""
function CoordinateSystem(d::Direction)
    return d.coordinate_system
end

"""
    Base.:*(s::Real, d::Direction) -> Direction

Scales a `Direction` object by a real scalar `s`.

Note that scaling a `Direction` object typically means scaling its underlying
vector components, but the resulting `Direction` object's `point` field
will still be normalized.

# Arguments
- `s::Real`: The scalar value.
- `d::Direction`: The `Direction` object.

# Returns
- A new `Direction` object with its `point` components scaled and then normalized.
"""
Base.:*(s::Real, d::Direction) = Direction(s * d.point, d.coordinate_system)
"""
    Base.:*(d::Direction, s::Real) -> Direction

Scales a `Direction` object by a real scalar `s` (scalar on the right).

Note that scaling a `Direction` object typically means scaling its underlying
vector components, but the resulting `Direction` object's `point` field
will still be normalized.

# Arguments
- `d::Direction`: The `Direction` object.
- `s::Real`: The scalar value.

# Returns
- A new `Direction` object with its `point` components scaled and then normalized.
"""
Base.:*(d::Direction, s::Real) = Direction(d.point * s, d.coordinate_system)
"""
    Base.:*(q::Quantity, d::Direction) -> Coordinate

Multiplies a `Quantity` (with units of length) by a `Direction` to create a `Coordinate`.

This operation effectively creates a `Coordinate` at a distance `q` along the direction `d`
from the origin of the `Direction`'s coordinate system.

# Arguments
- `q::Quantity`: A quantity with units of length (e.g., `10u"m"`).
- `d::Direction`: The `Direction` object.

# Returns
- A `Coordinate` object.
"""
Base.:*(q::Quantity, d::Direction) = Coordinate(q * d.point, d.coordinate_system)
"""
    Base.:*(d::Direction, q::Quantity) -> Coordinate

Multiplies a `Direction` by a `Quantity` (with units of length) to create a `Coordinate`.

This operation effectively creates a `Coordinate` at a distance `q` along the direction `d`
from the origin of the `Direction`'s coordinate system.

# Arguments
- `d::Direction`: The `Direction` object.
- `q::Quantity`: A quantity with units of length (e.g., `10u"m"`).

# Returns
- A `Coordinate` object.
"""
Base.:*(d::Direction, q::Quantity) = Coordinate(d.point * q, d.coordinate_system)

"""
    LinearAlgebra.dot(d1::Direction, d2::Direction) -> Real

Computes the dot product of two `Direction` objects.

Both `Direction` objects must be defined in the same coordinate system.

# Arguments
- `d1::Direction`: The first `Direction`.
- `d2::Direction`: The second `Direction`.

# Returns
- A `Real` value representing the dot product of their underlying vectors.
"""
LinearAlgebra.dot(d1::Direction, d2::Direction) = dot(d1.point, d2.point)
"""
    LinearAlgebra.cross(d1::Direction, d2::Direction) -> SVector{3,T}

Computes the cross product of two `Direction` objects.

Both `Direction` objects must be defined in the same coordinate system.
The result is an `SVector` representing the cross product of their underlying vectors.

# Arguments
- `d1::Direction`: The first `Direction`.
- `d2::Direction`: The second `Direction`.

# Returns
- An `SVector{3,T}` representing the cross product.
"""
LinearAlgebra.cross(d1::Direction, d2::Direction) = cross(d1.point, d2.point)

"""
    Base.convert(target_cs::CoordinateSystem, dir::Direction) -> Direction

Converts a `Direction` object from its current coordinate system to a `target_cs`.

This function applies the necessary inverse transformations to move the direction
from its original system to a global reference, and then applies the transformations
to place it in the `target_cs`.

# Arguments
- `target_cs::CoordinateSystem`: The target coordinate system.
- `dir::Direction`: The `Direction` object to convert.

# Returns
- A new `Direction` object in the `target_cs`.
"""
function Base.convert(coordinate_system::CoordinateSystem, dir::Direction)
    if coordinate_system==dir.coordinate_system
        return dir
    end
    r1 = LinearMap(RotMatrix(dir.coordinate_system.rotation))
    r2 = LinearMap(RotMatrix(coordinate_system.rotation))
    point = inv(r1)(dir.point)
    point = r2(point)

    return Direction(point, coordinate_system)
end

"""
    Base.reverse(d::Direction) -> Direction

Returns a new `Direction` object that points in the opposite direction of `d`.

# Arguments
- `d::Direction`: The `Direction` object to reverse.

# Returns
- A new `Direction` object pointing in the opposite direction.
"""
function Base.reverse(d::Direction)
    return Direction(-d.point, d.coordinate_system)
end
