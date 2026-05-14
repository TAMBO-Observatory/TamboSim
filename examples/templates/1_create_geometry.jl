# 1_create_geometry.jl
#
# Build a self-contained TamboSim geometry bundle for a site. Writes four files
# under `<outdir>/`, all stemmed by `<name>`:
#
#   <name>.jld2                Self-contained GCD bundle, loaded directly by
#                              downstream TamboSim simulation runs
#   <name>.h5                  HDF5 export (derived from the JLD2 bundle)
#   <name>_terrain.ply         Binary PLY for CORSIKA's tambo_shower
#   <name>_obs_surface.ply     Binary PLY for CORSIKA, detector region only
#
# HDF5 schema (under group `<name>`):
#   location   - [lon, lat] in degrees
#   radii      - PREM layer radii in m (13 values)
#   vertices   - (n_verts, 3) ECEF positions in m
#   faces      - (n_faces, 3) 1-based vertex indices
#   detector1  - 1-based face indices for the detector region
#
# The terrain itself is built by `build_terrain_patch` (defined below), a
# flat-square placeholder. For real topography, replace it with a function
# that interpolates DEM data (e.g. GEBCO earth_relief). The CLI flags split
# into two groups accordingly:
#
#   - --name, --outdir         general script args, inherent to the script's
#                              identity and output location
#
#   - --lon, --lat,            coupled to the placeholder build_terrain_patch
#     --elevation,             — a real DEM replacement would likely take
#     --half-width-km,         different inputs (DEM file path, bounding box,
#     --n-cells                sampling density, etc.) and these flags would
#                              change with the function.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using HDF5
using LinearAlgebra
using Unitful
using TamboSim

# PREM model radii (km → m)
const PREM_RADII_KM = [1221.5, 3480.0, 3630.0, 5600.0, 5701.0, 5771.0,
                       5971.0, 6151.0, 6291.0, 6346.6, 6356.0, 6368.0, 6371.0]

# =============================================================================
# Terrain patch builder
# =============================================================================

# This function is a placeholder -- replace with something physical!
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

    up    = TamboSim.longlat_to_cart(lon_rad, lat_rad)
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
# Main
# =============================================================================

function parse_commandline()
    s = ArgParseSettings(
        description = "Build a TamboSim geometry JLD2 bundle for a custom site"
    )

    @add_arg_table! s begin
        # --- General script args ---
        "--name", "-n"
            help = "Output-file stem and HDF5 group name"
            arg_type = String
            default = "custom_site"
        "--outdir", "-o"
            help = "Output directory"
            arg_type = String
            default = joinpath(dirname(@__DIR__), "output", "geometry")

        # --- Placeholder build_terrain_patch args ---
        "--lon"
            help = "(placeholder) Site longitude in degrees"
            arg_type = Float64
            default = -72.5
        "--lat"
            help = "(placeholder) Site latitude in degrees"
            arg_type = Float64
            default = -15.6
        "--elevation"
            help = "(placeholder) Site elevation above PREM surface in metres"
            arg_type = Float64
            default = 3_500.0
        "--half-width-km"
            help = "(placeholder) Terrain patch half-width in km"
            arg_type = Float64
            default = 50.0
        "--n-cells"
            help = "(placeholder) Cells per side in the terrain mesh (2 n_cells² triangles total)"
            arg_type = Int
            default = 30
    end

    return parse_args(s)
end

args = parse_commandline()

lon_deg     = args["lon"]
lat_deg     = args["lat"]
elevation_m = args["elevation"]
groupname   = args["name"]
outdir      = args["outdir"]
mkpath(outdir)

g_path          = joinpath(outdir, "$(groupname).jld2")
h5_path         = joinpath(outdir, "$(groupname).h5")
corsika_terrain = joinpath(outdir, "$(groupname)_terrain.ply")
corsika_obs     = joinpath(outdir, "$(groupname)_obs_surface.ply")

# --- Build mesh ---
vertices, faces, detector_indices = build_terrain_patch(
    lon_deg, lat_deg, elevation_m;
    half_width_km = args["half-width-km"],
    n_cells       = args["n-cells"],
)

longlat_rad = (deg2rad(lon_deg), deg2rad(lat_deg))
prem_radii  = PREM_RADII_KM .* 1_000.0 .* u"m"

# --- 1. Primary output: JLD2 GCD bundle ---
println("Building GCD bundle...")
frames = TamboSim.build_gcd_bundle(vertices, faces, longlat_rad, prem_radii, detector_indices)
save_frames(g_path, frames, streams=('G', 'C', 'D'))
println("  Saved → $g_path ($(round(filesize(g_path)/1024^2, digits=1)) MB)")

# Verify round-trip: reload from JLD2.
frames2  = load_frames(g_path)
g_frame2 = frames2.g_frames[end]
d_frame2 = frames2.d_frames[end]
n_prem   = length(g_frame2["prem"])
n_tris   = length(g_frame2["topography"])
n_det    = length(d_frame2["detector_region"])
println("  Reloaded — PREM layers: $n_prem  triangles: $n_tris  detector faces: $n_det")

g_frame = frames.g_frames[end]
d_frame = frames.d_frames[end]

# --- 2. HDF5 export (derived) ---
TamboSim.dump_to_h5(g_frame, d_frame, h5_path, groupname)
println("HDF5: wrote $h5_path:$groupname")

# --- 3. Binary PLYs for CORSIKA ---
TamboSim.dump_to_ply(g_frame, corsika_terrain; watertight_depth=10_000.0)
println("Binary PLY (terrain): wrote $corsika_terrain")

TamboSim.dump_to_ply(d_frame, corsika_obs)
println("Binary PLY (obs surface): wrote $corsika_obs")

println("\nAll geometry files written to $outdir")
