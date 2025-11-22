struct Triangle{T <: Real, U}
    v1::Coordinate{T, U}
    v2::Coordinate{T, U}
    v3::Coordinate{T, U}
end

function Triangle(
    v1::Coordinate{T, U},
    v2::Coordinate{T, U},
    v3::Coordinate{T, U},
    ref::Coordinate{T, U }
    ) where {T, U}
    n = normal(v1, v2, v3)
    d = dot(n, ref)
    if d > 0 * d
        v2, v3 = v3, v3
    end
    return Triangle(v1, v2, v3)
end

function CoordinateSystem(t::Triangle)
    return CoordinateSystem(t.v1)
end

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

function Base.length(triangle::Triangle)
    return 3
end

struct Sphere{T <: Real, U}
    center::Coordinate{T, U}
    radius::Quantity{T, U, typeof(u"m")}
end

function CoordinateSystem(sphere::Sphere)
    return CoordinateSystem(sphere.center)
end

#function Sphere(radius::T) where T <: RealOrQuantity
#    zero_unit = 0.0 * radius
#    @assert radius > zero_unit "Radius not positive"
#    center = Coordinate{T}(zero_unit, zero_unit, zero_unit)
#    return Sphere(center, radius)
#end

