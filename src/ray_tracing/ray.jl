struct Ray{T<:Real}
    origin::Coordinate{T}
    direction::Direction{T}

    function Ray(origin::Coordinate{T}, direction::Direction{T}) where {T<:Real}
        origin.coordinate_system==direction.coordinate_system || throw("Coordinate system mismatch")
        new{T}(origin, direction)
    end
end

Base.reverse(ray::Ray) = Ray(ray.origin, reverse(ray.direction))
