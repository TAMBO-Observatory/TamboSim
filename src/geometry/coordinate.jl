struct Coordinate{T <: Real, U}
    point::SVector{3, Quantity{T, U, typeof(u"m")}}
    coordinate_system::CoordinateSystem{T, U}
    function Coordinate(point::AbstractVector{<:Quantity}, cs::CoordinateSystem)
        point_sv = SVector{3}(point)
        U = dimension(point_sv.x)
        T = promote_type(eltype(cs), eltype(one(point_sv.x)))
        new{T, U}(point_sv, cs)
    end
end

function Coordinate(x, y, z, cs::CoordinateSystem)
    return Coordinate([x, y, z], cs)
end

function CoordinateSystem(c::Coordinate)
    return c.coordinate_system
end

Base.eltype(c::Coordinate) = eltype(c.coordinate_system)
Base.size(c::Coordinate) = (3,)
Base.length(c::Coordinate) = 3
Base.getindex(c::Coordinate, i) = c.point[i]
function Base.iterate(c::Coordinate, state=1)
    state > length(c) && return nothing
    return (c.point[state], state + 1)
end

function Base.:+(a::Coordinate, b::Coordinate)
    check_coordinate_systems(a, b)
    return Coordinate(a.point + b.point, a.coordinate_system)
end

function Base.:-(a::Coordinate, b::Coordinate)
    check_coordinate_systems(a, b)
    return Coordinate(a.point - b.point, a.coordinate_system)
end

Base.Broadcast.broadcastable(coord::Coordinate) = (coord,)

# Generic function to handle both min and max
function coordinate_extremum(f::Function, coords::Coordinate...)
    cs = first(coords).coordinate_system
    for coord in coords
        coord.coordinate_system == cs || error("Coordinate systems must match")
    end

    points = [c.point for c in coords]
    result_point = SVector{3}(
        f(p[1] for p in points),
        f(p[2] for p in points),
        f(p[3] for p in points)
    )

    return Coordinate(result_point, cs)
end

# Define broadcasted for max
function Base.broadcasted(::typeof(max), coords::Coordinate...)
    return coordinate_extremum(maximum, coords...)
end

# Define broadcasted for min
function Base.broadcasted(::typeof(min), coords::Coordinate...)
    return coordinate_extremum(minimum, coords...)
end
#Base.Broadcast.broadcastable(coord::Coordinate) = Ref(coord)
#
## Define how to broadcast max between Coordinates
#function Base.broadcasted(::typeof(max), a::Coordinate, b::Coordinate)
#    # Check coordinate systems
#    if a.coordinate_system != b.coordinate_system
#        error("Cannot max Coordinates with different coordinate systems")
#    end
#
#    # Compute max for each component
#    max_point = SVector{3}(
#        max(a.point[1], b.point[1]),
#        max(a.point[2], b.point[2]),
#        max(a.point[3], b.point[3])
#    )
#
#    return Coordinate(max_point, a.coordinate_system)
#end
#
## Handle broadcasting with multiple coordinates
#function Base.broadcasted(::typeof(max), coords::Coordinate...)
#    # All coordinate systems must match
#    cs = first(coords).coordinate_system
#    for coord in coords
#        if coord.coordinate_system != cs
#            error("All Coordinates must have the same coordinate system for broadcasting")
#        end
#    end
#
#    # Find max along each dimension
#    points = [c.point for c in coords]
#    max_x = maximum(p[1] for p in points)
#    max_y = maximum(p[2] for p in points)
#    max_z = maximum(p[3] for p in points)
#
#    max_point = SVector{3}(max_x, max_y, max_z)
#    return Coordinate(max_point, cs)
#end

Base.:*(a::Coordinate, s::Number) = Coordinate(a.point * s, a.coordinate_system)
Base.:/(a::Coordinate, s::Number) = Coordinate(a.point / s, a.coordinate_system)
Base.:*(s::Number, a::Coordinate) = Coordinate(s * a.point, a.coordinate_system)

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
