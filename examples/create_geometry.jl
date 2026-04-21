"""
create_geometry.jl

Build a custom Tambo geometry HDF5 file for an arbitrary location and load
it back with Earth to verify correctness.

HDF5 schema written under a group key:
  location   - [lon, lat] in degrees
  radii      - PREM layer radii in metres (13 values)
  vertices   - (n_verts, 3) ECEF positions in metres
  faces      - (n_faces, 3) 1-based vertex indices
  detector1  - 1-based face indices for the detector region

The geometry is a flat rectangular terrain patch centred on a user-supplied
lon/lat/elevation.  For a realistic geometry, replace build_terrain_patch
with a function that interpolates actual DEM data (e.g. GEBCO earth_relief).
"""

using HDF5
using LinearAlgebra
using Tambo

# PREM model radii (km → m)
const PREM_RADII_KM = [1221.5, 3480.0, 3630.0, 5600.0, 5701.0, 5771.0,
                       5971.0, 6151.0, 6291.0, 6346.6, 6356.0, 6368.0, 6371.0]

"""
    build_terrain_patch(lon_deg, lat_deg, elevation_m; half_width_km, n_cells)

Generate a flat rectangular terrain patch centred at the given lon/lat/elevation.

Returns:
- `vertices`         — (n_verts, 3) ECEF positions in metres
- `faces`            — (n_faces, 3) 1-based vertex indices, outward normals
- `detector_indices` — 1-based face indices for the central detector region
"""
function build_terrain_patch(
    lon_deg     :: Real,
    lat_deg     :: Real,
    elevation_m :: Real;
    half_width_km :: Real = 50.0,
    n_cells       :: Int  = 20
)
    lon_rad  = deg2rad(lon_deg)
    lat_rad  = deg2rad(lat_deg)
    r_surface = PREM_RADII_KM[end] * 1_000.0 + elevation_m

    # Local ENU basis at the site
    up    = Tambo.longlat_to_cart(lon_rad, lat_rad)
    east  = normalize([-sin(lon_rad), cos(lon_rad), 0.0])
    north = normalize(cross(up, east))

    half_width_m = half_width_km * 1_000.0
    xs = range(-half_width_m, half_width_m; length=n_cells + 1)
    ys = range(-half_width_m, half_width_m; length=n_cells + 1)

    n_verts  = (n_cells + 1)^2
    vertices = Matrix{Float64}(undef, n_verts, 3)
    for (j, y) in enumerate(ys), (i, x) in enumerate(xs)
        idx = (j - 1) * (n_cells + 1) + i
        vertices[idx, :] = up .* r_surface .+ east .* x .+ north .* y
    end

    # Two triangles per grid cell; winding order gives outward normals
    n_faces = 2 * n_cells^2
    faces   = Matrix{Int}(undef, n_faces, 3)
    fi = 1
    for j in 1:n_cells, i in 1:n_cells
        bl = (j - 1) * (n_cells + 1) + i
        br, tl, tr = bl + 1, bl + (n_cells + 1), bl + (n_cells + 1) + 1
        faces[fi,     :] = [bl, br, tr]
        faces[fi + 1, :] = [bl, tr, tl]
        fi += 2
    end

    # Mark the central quarter as the detector region
    center_ecef      = up .* r_surface
    detector_indices = Int[]
    for f in 1:n_faces
        cen = (vertices[faces[f, 1], :] .+
               vertices[faces[f, 2], :] .+
               vertices[faces[f, 3], :]) ./ 3.0
        dx = dot(cen .- center_ecef, east)
        dy = dot(cen .- center_ecef, north)
        if abs(dx) <= half_width_m / 2 && abs(dy) <= half_width_m / 2
            push!(detector_indices, f)
        end
    end

    return vertices, faces, detector_indices
end

"""
    write_geometry(path, groupname, lon_deg, lat_deg, elevation_m; kwargs...)

Build a flat terrain patch and write it to `path` under `groupname`.
"""
function write_geometry(
    path        :: String,
    groupname   :: String,
    lon_deg     :: Real,
    lat_deg     :: Real,
    elevation_m :: Real;
    kwargs...
)
    vertices, faces, detector_indices = build_terrain_patch(
        lon_deg, lat_deg, elevation_m; kwargs...
    )

    radii_m = PREM_RADII_KM .* 1_000.0

    h5open(path, "cw") do f
        haskey(f, groupname) && delete_object(f, groupname)
        g              = create_group(f, groupname)
        g["location"]  = Float64[lon_deg, lat_deg]
        g["radii"]     = radii_m
        g["vertices"]  = vertices
        g["faces"]     = faces
        g["detector1"] = detector_indices
    end

    println("Wrote $(size(faces, 1)) triangles to $path:$groupname")
    println("  Detector region: $(length(detector_indices)) triangles")
    return path, groupname
end

# Example: Valley of the Volcanoes, Peru
lon_deg     = -72.5
lat_deg     = -15.6
elevation_m = 3_500.0
output_path = joinpath(@__DIR__, "output", "custom_geometry.h5")
groupname   = "custom_site"

mkpath(dirname(output_path))
write_geometry(output_path, groupname, lon_deg, lat_deg, elevation_m;
               half_width_km=50.0, n_cells=30)

# Load back with Earth to verify the schema is correct
println("\nLoading geometry with Earth...")
earth = Earth("$output_path:$groupname", "detector1")
println("  PREM layers:    $(length(earth.prem))")
println("  Triangles:      $(length(earth.triangles))")
println("  Detector faces: $(length(earth.detector_region))")
println("\nGeometry is valid and ready for simulation.")
