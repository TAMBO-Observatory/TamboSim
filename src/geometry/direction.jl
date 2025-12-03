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

function Direction(point::Vector, coordinate_system::CoordinateSystem)
    @assert length(point)==3
    return Direction(SVector{3}(point), coordinate_system)
end

Base.size(d::Direction) = (3,)
Base.length(d::Direction) = 3
Base.getindex(d::Direction, i) = d.point[i]

Base.:*(s::Real, d::Direction) = Direction(s * d.point, d.coordinate_system)
Base.:*(d::Direction, s::Real) = Direction(d.point * s, d.coordinate_system)
Base.:*(q::Quantity, d::Direction) = Coordinate(q * d.point, d.coordinate_system)
Base.:*(d::Direction, s::Quantity) = Coordinate(d.point * q, d.coordinate_system)

LinearAlgebra.dot(d1::Direction, d2::Direction) = dot(d1.point, d2.point)

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

function Base.reverse(d::Direction)
    return Direction(-d.point, d.coordinate_system)
end
