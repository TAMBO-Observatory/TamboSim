function centroid(triangle::Triangle)
    p = triangle.v1 + triangle.v2 + triangle.v3
    return p / 3
end

function check_coordinate_systems(coord1::Coordinate, coord2::Coordinate)
    @assert coord1.coordinate_system==coord2.coordinate_system "Incompatible coordinate systems"
end

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

function longlat_to_cart(long, lat)
    return [cos(long) * cos(lat), sin(long) * cos(lat), sin(lat)]
end

function cart_to_longlat(x, y, z)
    n = norm([x, y, z])
    x, y, z = [x, y, z] ./ n
    return [atan(y, x), asin(z)]
end

function cart_to_longlat(c::Coordinate)
    c = convert(ecefcoordinates, c)
    cart_to_longlat(c.point...)
end

function sph_to_cart(theta, phi)
    return [cos(phi) * sin(theta), sin(theta) * sin(phi), cos(theta)]
end

function cart_to_sph(d::Direction)
    return acos(d.point.z), atan(d.point.y, d.point.x)
end

function normal(v1::AbstractVector, v2::AbstractVector, v3::AbstractVector)
    (length(v1)==3 && length(v3)==3 && length(v3)==3) || throw("Can't take cross product")
    edge1 = v1 - v2
    edge2 = v1 - v3
    n = cross(edge1, edge2)
    n /= norm(n)

end

function normal(v1::Coordinate{T,U}, v2::Coordinate{T,U}, v3::Coordinate{T,U}) where {T,U}
    CoordinateSystem(v1)==CoordinateSystem(v2)==CoordinateSystem(v3) || throw("incompatible coordinate systems")
    edge1 = v1.point - v2.point
    edge2 = v1.point - v3.point
    n = cross(edge1, edge2)
    n /= norm(n)
    return Direction(n, CoordinateSystem(v1))
end

function normal(triangle::Triangle{T,U}) where {T,U}
    return normal(triangle.v1, triangle.v2, triangle.v3)
end

function area(triangle::Triangle{T,U})::Quantity{T,U^2,typeof(u"m^2")} where {T,U}
    a = triangle.v2.point - triangle.v1.point
    b = triangle.v3.point - triangle.v1.point

    cross_product = cross(a, b)

    return 0.5 * norm(cross_product)
end

function validate_triangle(triangle::Triangle{T,U}, center::Coordinate{T,U}) where {T,U}
    cent = centroid(triangle)
    n1 = normal(triangle)
    n2 = normalize(cent.point - center.point)
    return dot(n1.point, n2) > 0
end

function StatsBase.sample(t::Triangle)
    r1 = rand()
    r2 = rand()

    if r1 + r2 > 1
        r1 = 1 - r1
        r2 = 1 - r2
    end

    return (1 - r1 - r2) * t.v1 + r1 * t.v2 + r2 * t.v3
end
