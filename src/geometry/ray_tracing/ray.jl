struct Ray{T <: Real, U}
    origin::Coordinate{T, U}
    direction::Direction{T}

    function Ray(origin::Coordinate{T, U}, direction::Direction{T}) where {T, U}
        origin.coordinate_system==direction.coordinate_system || throw("Coordinate system mismatch")
        new{T, U}(origin, direction)
    end
end
