function centroid(triangle::Triangle)
    p = triangle.v1 + triangle.v2 + triangle.v3
    return p/3
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

function normal(v1::Coordinate, v2::Coordinate, v3::Coordinate)
    edge1 = v1.point - v2.point
    edge2 = v1.point - v3.point
    n = cross(edge1, edge2)
    n /= norm(n)
    return n
end

function normal(triangle::Triangle)
    return normal(triangle.v1, transform.v2, transform.v3)
end
