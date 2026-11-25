# site_mesh.jl — place the base triangulation on a site and give it DEM heights (functions only;
# included by create_geometry_from_kml.jl, which also includes copernicus_dem.jl).

using LinearAlgebra
using Rotations

longlat_to_cart(lon::Real, lat::Real) = [cos(lon)*cos(lat), sin(lon)*cos(lat), sin(lat)]

function cart_to_longlat(x::Real, y::Real, z::Real)
    r = sqrt(x^2 + y^2 + z^2)
    return [atan(y/r, x/r), asin(z/r)]
end

"Rotation taking the north pole to the site at `longlat0_rad`."
function site_rotation(longlat0_rad)
    target = longlat_to_cart(longlat0_rad...)
    north_pole = [0.0, 0.0, 1.0]
    AngleAxis(acos(clamp(dot(north_pole, target), -1.0, 1.0)), cross(north_pole, target)...)
end

"""
Radii (km) of the inner cap and ring of a pole-centred base triangulation built with equal point
counts per zone (as in triangulation.h5): the distances from the pole enclosing 1/3 and 2/3 of
the vertices.
"""
function zone_radii_km(verts_deg)
    d = sort(6371.0 .* deg2rad.(90 .- verts_deg[:, 2]))
    n = length(d)
    (d[n ÷ 3], d[2n ÷ 3])
end

"""
Lon/lat extremes (lon_min, lon_max, lat_min, lat_max) of a circle of `radius_km` around the
site, for checking which DEM tiles / latitudes a build needs. Longitude half-width uses the
circle's most poleward latitude, so the box always contains the circle.
"""
function circle_extent_deg(longlat0_deg, radius_km)
    dlat = rad2deg(radius_km / 6371.0)
    lat_far = min(abs(longlat0_deg[2]) + dlat, 89.999)
    dlon = rad2deg(radius_km / (6371.0 * cosd(lat_far)))
    (longlat0_deg[1] - dlon, longlat0_deg[1] + dlon, longlat0_deg[2] - dlat, longlat0_deg[2] + dlat)
end

"Great-circle distance (km, 6371 km sphere) of each base vertex from the pole = from the site after rotation."
pole_distance_km(verts_deg) = 6371.0 .* deg2rad.(90 .- verts_deg[:, 2])

"""
    build_ecef_vertices(verts_deg, longlat0_deg, radius_km, dem, R; tile_dir) -> (ecef, n_dem)

Rotate the north-pole-centred base triangulation to `longlat0_deg`. Vertices within `radius_km`
(great-circle distance) of the site get the DEM height, bilinear at the vertex lon/lat; the rest
stay on the sphere of radius `R` (m), i.e. at 0 m. Returns an (N, 3) matrix of ECEF positions in
metres and the number of DEM vertices.
"""
function build_ecef_vertices(verts_deg, longlat0_deg, radius_km, dem, R; tile_dir=nothing)
    rot = site_rotation(deg2rad.(longlat0_deg))
    n = size(verts_deg, 1)
    lonlat_rad = Matrix{Float64}(undef, n, 2)
    for i in 1:n
        lonlat_rad[i, :] .= cart_to_longlat((rot * longlat_to_cart(deg2rad.(verts_deg[i, :])...))...)
    end
    lonlat = rad2deg.(lonlat_rad)
    in_circle = pole_distance_km(verts_deg) .<= radius_km    # rotation preserves distances from the pole
    println("  DEM heights within $(radius_km) km of the centre: $(count(in_circle)) vertices")
    itp = dem_interp(dem, lonlat[in_circle, 1], lonlat[in_circle, 2]; tile_dir=tile_dir)

    ecef = zeros(n, 3)
    for i in 1:n
        r = in_circle[i] ? R + itp(lonlat[i, 1], lonlat[i, 2]) : R
        ecef[i, :] = longlat_to_cart(lonlat_rad[i, :]...) .* r
    end
    return ecef, count(in_circle)
end
