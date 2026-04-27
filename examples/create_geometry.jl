"""
create_geometry.jl

Build a Tambo geometry HDF5 file for an arbitrary site, export it to the
PLY formats used downstream, and save a self-contained G frame JLD2.

  1. HDF5 — primary source format; contains terrain mesh, PREM radii, site
             coordinates, and detector region face indices.

  2. ASCII PLY — general-purpose mesh with per-face is_in_injection flag and
                 a custom radii element.

  3. Binary PLY (CORSIKA) — binary_little_endian mesh required by the CORSIKA 8
                             tambo_shower module.  Two files are written:
                               custom_terrain.ply     — full terrain mesh
                               custom_obs_surface.ply — detector region only

  4. JLD2 G frame — self-contained geometry frame (mesh + BVH + coordinate
                    system).  Downstream simulation runs can load this directly
                    with load_frames("geometry.jld2") without needing the HDF5
                    file.

HDF5 schema written under the group key:
  location   - [lon, lat] in degrees
  radii      - PREM layer radii in metres (13 values)
  vertices   - (n_verts, 3) ECEF positions in metres
  faces      - (n_faces, 3) 1-based vertex indices
  detector1  - 1-based face indices for the detector region

For a realistic geometry replace build_terrain_patch with a function that
interpolates actual DEM data (e.g. GEBCO earth_relief).
"""

using HDF5
using LinearAlgebra
using Tambo

# PREM model radii (km → m)
const PREM_RADII_KM = [1221.5, 3480.0, 3630.0, 5600.0, 5701.0, 5771.0,
                       5971.0, 6151.0, 6291.0, 6346.6, 6356.0, 6368.0, 6371.0]

# =============================================================================
# Terrain patch builder
# =============================================================================

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
    lon_rad   = deg2rad(lon_deg)
    lat_rad   = deg2rad(lat_deg)
    r_surface = PREM_RADII_KM[end] * 1_000.0 + elevation_m

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

    # Two triangles per cell; winding order produces outward normals
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

# =============================================================================
# HDF5 writer
# =============================================================================

"""
    write_geometry_h5(path, groupname, lon_deg, lat_deg, elevation_m; kwargs...)

Build a flat terrain patch and write it to `path` under `groupname`.
"""
function write_geometry_h5(
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

    println("HDF5: wrote $(size(faces, 1)) triangles to $path:$groupname")
    println("  Detector region: $(length(detector_indices)) triangles")
    return vertices, faces, detector_indices
end

# =============================================================================
# ASCII PLY writer (loaded by earth_from_ply)
# =============================================================================

"""
    write_geometry_ply(path, vertices, faces, detector_indices, radii_m)

Write an ASCII PLY file compatible with earth_from_ply().

Per-face `is_in_injection` (uchar) marks detector region triangles.
A custom `radii` element stores the PREM layer radii.
"""
function write_geometry_ply(
    path             :: String,
    vertices         :: Matrix{Float64},
    faces            :: Matrix{Int},
    detector_indices :: Vector{Int},
    radii_m          :: Vector{Float64}
)
    n_verts = size(vertices, 1)
    n_faces = size(faces, 1)
    det_set = Set(detector_indices)

    open(path, "w") do io
        write(io, "ply\nformat ascii 1.0\n")
        write(io, "element vertex $n_verts\n")
        write(io, "property double x\nproperty double y\nproperty double z\n")
        write(io, "element face $n_faces\n")
        write(io, "property list uchar int vertex_indices\n")
        write(io, "property uchar is_in_injection\n")
        write(io, "element radii $(length(radii_m))\nproperty double value\n")
        write(io, "end_header\n")
        for i in 1:n_verts
            write(io, "$(vertices[i,1]) $(vertices[i,2]) $(vertices[i,3])\n")
        end
        for i in 1:n_faces
            a, b, c = faces[i,1]-1, faces[i,2]-1, faces[i,3]-1
            write(io, "3 $a $b $c $(i in det_set ? 1 : 0)\n")
        end
        for r in radii_m
            write(io, "$r\n")
        end
    end
    println("ASCII PLY: wrote $path")
end

# =============================================================================
# Binary PLY writer (required by CORSIKA tambo_shower)
# =============================================================================

"""
    write_corsika_ply(path, vertices, faces)

Write a binary_little_endian PLY file for CORSIKA.

Vertices are Float64; face lists use UInt8 count + UInt32 0-based indices.
"""
function write_corsika_ply(path::String, vertices::Matrix{Float64}, faces::Matrix{Int})
    open(path, "w") do io
        print(io, "ply\nformat binary_little_endian 1.0\n")
        print(io, "element vertex $(size(vertices,1))\n")
        print(io, "property double x\nproperty double y\nproperty double z\n")
        print(io, "element face $(size(faces,1))\n")
        print(io, "property list uchar uint vertex_indices\n")
        print(io, "end_header\n")
        for i in axes(vertices, 1)
            write(io, htol(vertices[i,1]), htol(vertices[i,2]), htol(vertices[i,3]))
        end
        for i in axes(faces, 1)
            write(io, UInt8(3),
                  htol(UInt32(faces[i,1]-1)),
                  htol(UInt32(faces[i,2]-1)),
                  htol(UInt32(faces[i,3]-1)))
        end
    end
    println("Binary PLY: wrote $path")
end

function detector_subset(vertices::Matrix{Float64}, faces::Matrix{Int}, detector_indices::Vector{Int})
    det_faces = faces[detector_indices, :]
    used      = sort(unique(vec(det_faces)))
    remap     = Dict(old => new for (new, old) in enumerate(used))
    sub_verts = vertices[used, :]
    sub_faces = [remap[det_faces[i,j]] for i in axes(det_faces,1), j in 1:3]
    return sub_verts, sub_faces
end

# =============================================================================
# Main
# =============================================================================

lon_deg     = -72.5
lat_deg     = -15.6
elevation_m = 3_500.0
groupname   = "custom_site"
outdir      = joinpath(@__DIR__, "output")
mkpath(outdir)

h5_path          = joinpath(outdir, "custom_geometry.h5")
ply_path         = joinpath(outdir, "custom_geometry.ply")
corsika_terrain  = joinpath(outdir, "custom_terrain.ply")
corsika_obs      = joinpath(outdir, "custom_obs_surface.ply")

# --- 1. HDF5 ---
vertices, faces, detector_indices = write_geometry_h5(
    h5_path, groupname, lon_deg, lat_deg, elevation_m;
    half_width_km=50.0, n_cells=30
)

# --- Build and save GCD bundle ---
# build_gcd_bundle reads the HDF5 and produces G + blank C + D frames.
# Saving with streams=('G','C','D') produces a self-contained JLD2 — downstream
# simulation runs use load_frames("geometry.jld2") and never touch the HDF5.
println("\nBuilding GCD bundle and saving to JLD2...")
g_path = joinpath(outdir, "geometry.jld2")
frames = Tambo.build_gcd_bundle("$h5_path:$groupname", "detector1")
save_frames(g_path, frames, streams=('G', 'C', 'D'))
println("  Saved → $g_path ($(round(filesize(g_path)/1024^2, digits=1)) MB)")

# Verify round-trip: reload from JLD2 (no HDF5 file needed).
frames2 = load_frames(g_path)
gframe2 = get_frame(frames2, 'G')
dframe2 = get_frame(frames2, 'D')
n_prem   = length(gframe2["prem"])
n_tris   = length(gframe2["topography"])
n_det    = length(dframe2["detector_region"])
println("  Reloaded — PREM layers: $n_prem  triangles: $n_tris  detector faces: $n_det")

# --- 2. ASCII PLY (for earth_from_ply) ---
write_geometry_ply(ply_path, vertices, faces, detector_indices, PREM_RADII_KM .* 1_000.0)

# --- 3. Binary PLY for CORSIKA ---
write_corsika_ply(corsika_terrain, vertices, faces)

sub_verts, sub_faces = detector_subset(vertices, faces, detector_indices)
write_corsika_ply(corsika_obs, sub_verts, sub_faces)

println("\nAll geometry files written to $outdir")
