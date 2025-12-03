struct Plane{T}
    point::Coordinate{T}
    normal::Direction{T}
    function Plane(point::Coordinate{T}, normal::Direction{T}) where T
        @assert CoordinateSystem(point)==CoordinateSystem(point)
        return new{T}(point, normal)
    end
end

function Base.convert(cs::CoordinateSystem{T}, plane::Plane{T}) where {T<:Real}
    if CoordinateSystem(plane.point)==cs
        return plane
    end
    return Plane(convert(cs, plane.point), convert(cs, plane.normal))
end
