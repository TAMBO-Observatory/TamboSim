struct Coord{T<:Float64}
    latitude::T
    longitude::T
end

function mincoord_fromfile(filename)
    open(filename) do file
        latmin = 0
        longmin = 0
        for (idx, line) in enumerate(eachline(file))
            if idx!=1
                splitline = split(line, "\t")
                lat = parse(Float64, splitline[2])
                long = parse(Float64, splitline[3])
                latmin = minimum([lat, latmin])
                longmin = minimum([long, longmin])
            end
        end
        return Coord(deg2rad(latmin), deg2rad(longmin))
    end
end

#function mincoord_fromfile()
#    filename = "$(@__DIR__)/../resources/ColcaValleyData.txt"
#    return mincoord_fromfile(filename)
#end

"""
    latlong_to_xy(lat, long, latmin, longmin)

TBW
"""
function latlong_to_xy(lat, long, latmin, longmin)
    r = 6_371.0 * units.km
    x = r * cos(latmin) * (long - longmin)
    y = r * (lat - latmin)
    return SVector{2}(x, y)
end

"""
    latlong_to_xy(coord::Coord, coordmin::Coord)

TBW
"""
function latlong_to_xy(coord::Coord, coordmin::Coord)
    return latlong_to_xy(
        coord.latitude,
        coord.longitude,
        coordmin.latitude,
        coordmin.longitude
    )
end

"""
    xy_to_latlong(x, y, latmin, longmin)

TBW
"""
function xy_to_latlong(x, y, latmin, longmin)
    r = 6_371.0 * units.km
    long = x / (r * cos(latmin)) + longmin
    lat = y / r + latmin
    return Coord(lat, long)
end

"""
    xy_to_latlong(xy, latmin, longmin)

TBW
"""
function xy_to_latlong(xy, latmin, longmin)
    return xy_to_latlong(xy[1], xy[2], latmin, longmin)
end

"""
    xy_to_latlong(xy, coordmin::Coord)

TBW
"""
function xy_to_latlong(xy, coordmin::Coord)
    return xy_to_latlong(xy, coordmin.latitude, coordmin.longitude)
end

const coords = (
    minesite=Coord(deg2rad(-15.664653), deg2rad(-72.1547479)),
    testsite = Coord(deg2rad(-15.58714), deg2rad(-71.9765237)),
    whitepaper = Coord(deg2rad(-15.63863),deg2rad(-72.16498)),
    larger_valley = Coord(deg2rad(-15.622267), deg2rad(-72.279397))
)
const normal_vecs = (
    larger_valley = Direction(0.507,0.108,0.855),
    whitepaper_normal = Direction(0.452174,-0.366163,0.813304),
    minesite_normal = Direction(-0.732001, 0.59897, 0.324666),
)

