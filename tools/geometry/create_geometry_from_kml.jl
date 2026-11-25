# create_geometry_from_kml.jl
#
# Build a TamboSim geometry bundle for a site outlined in a KML/KMZ file (any source: Google
# Earth Pro or web, QGIS, …). Rotates a north-pole-centred base triangulation onto the outline's
# area centroid, gives it DEM heights (Copernicus GLO-30 by default), and writes:
#
#   <name>.h5                  HDF5 source (same schema as examples/templates/1_create_geometry.jl)
#   <name>.jld2                Self-contained G, C, D bundle (D = detector region inside the outline)
#   <name>_terrain.ply         Binary PLY for CORSIKA tambo_shower (full closed mesh, as run_corsika writes it)
#   <name>_obs_surface.ply     Binary PLY for the CORSIKA observation surface
#
#   julia --project=tools tools/geometry/create_geometry_from_kml.jl --kml my_site.kmz [--placemark NAME]
#   julia --project=tools tools/geometry/create_geometry_from_kml.jl --kml my_site.kml --list
#   julia --project=tools tools/geometry/create_geometry_from_kml.jl --corners LAT1 LON1 LAT2 LON2 LAT3 LON3 LAT4 LON4
#
# The outline is either a KML placemark, selected by its name, id or "Comments" field (optional
# when the file has a single polygon placemark; all its Polygons form the outline, holes
# excluded), or a box given by --corners: four lat/lon points in order around the box.
# Defaults come from resources/: tambito_candidates_june23.kml (when neither --kml nor --corners
# is given) and triangulation.h5:base_triangulation_100000 (the TAMBITO base triangulation).
#
# Triangle sizes come entirely from the base triangulation (see README.md); the DEM only sets
# vertex heights. Vertices within --terrain-radius-km (great-circle distance, default 50 km =
# the triangulation's ring edge) of the centre get DEM heights; the rest stay on the 6371 km
# sphere at 0 m.
#
# Fixes relative to the pre-2026-11 version of this script (bundles built before then are affected):
#   1. DEM registration. Pixel-registered GMT grids come out of GMT.jl with n+1 cell EDGES; the
#      old script kept the first n, putting every value at its cell's SW corner, so all terrain was
#      drawn 7.5″ (≈ 230 m) S and W of its true position (≈ 6″ net for SRTM15+, see README.md).
#   2. DEM source. Copernicus GLO-30 (1″) replaces SRTM15+ (15″) by default; bilinear point
#      sampling replaces the Dierckx spline (impractical on a 1″ grid).
#   3. Site centre. The old vertex mean counted the KML ring's closing vertex twice (~220 m bias
#      for west of Huambo); the centre is now the polygon's area centroid.
#
# Note: EzXML emits a benign "ignored the empty prefix" warning for KML's default namespace.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using LinearAlgebra
using Statistics
using Unitful
using TamboSim

include(joinpath(@__DIR__, "src_jl", "copernicus_dem.jl"))
include(joinpath(@__DIR__, "src_jl", "kml_outline.jl"))
include(joinpath(@__DIR__, "src_jl", "site_mesh.jl"))

const RESOURCES = joinpath(@__DIR__, "resources")
const PREM_RADII_KM = [1221.5, 3480.0, 3630.0, 5600.0, 5701.0, 5771.0,
                       5971.0, 6151.0, 6291.0, 6346.6, 6356.0, 6368.0, 6371.0]
const COPERNICUS_MAX_LAT = 50.0   # GLO-30 tiles change longitude spacing above 50°

function parse_commandline()
    s = ArgParseSettings(description = "Build a TamboSim geometry bundle from a KML/KMZ outline (or four corner " *
                                       "points) + DEM + base triangulation")
    @add_arg_table! s begin
        "--kml"
            help     = "KML or KMZ file with the site outline(s) (default: resources/tambito_candidates_june23.kml)"
            arg_type = String
            default  = ""
        "--corners"
            help     = "Instead of a KML: four corners of the detector box as LAT LON pairs in degrees, " *
                       "in order around the box (either direction), e.g. --corners -15.757 -72.123 " *
                       "-15.745 -72.138 -15.740 -72.134 -15.752 -72.119"
            nargs    = 8
            arg_type = Float64
            metavar  = "LAT/LON"
        "--placemark"
            help     = "Name, id or Comments of the placemark to use as the detector outline " *
                       "(optional if the file has a single polygon placemark)"
            arg_type = String
            default  = ""
        "--list"
            help     = "List the placemarks in --kml and exit"
            action   = :store_true
        "--allow-outside-fine-mesh"
            help     = "Build without asking when the outline extends beyond the base triangulation's " *
                       "fine-mesh zone (otherwise the builder asks for confirmation, and stops if it cannot ask)"
            action   = :store_true
        "--triangulation"
            help     = "path.h5:group of the north-pole-centred base triangulation " *
                       "(vertices [N, 2] lon/lat in degrees, faces [M, 3]); groups base_triangulation_N " *
                       "hold N points per zone, see README.md"
            arg_type = String
            default  = joinpath(RESOURCES, "triangulation.h5") * ":base_triangulation_100000"
        "--dem"
            help     = "\"copernicus\" (GLO-30 tiles from AWS; recommended) or an HDF5 grid " *
                       "(longitude, latitude, elevation[n_lat, n_lon]), e.g. GMT earth_relief_15s.h5"
            arg_type = String
            default  = "copernicus"
        "--tile-dir"
            help     = "Directory to read/cache Copernicus tiles (default: a temporary directory, deleted after use)"
            arg_type = String
            default  = ""
        "--name", "-n"
            help     = "Output file stem (default: the placemark's name/id, or box_<lat>_<lon> of the centre for --corners)"
            arg_type = String
            default  = ""
        "--outdir", "-o"
            help     = "Output directory"
            arg_type = String
            default  = joinpath(@__DIR__, "..", "output", "geometry")
        "--terrain-radius-km"
            help     = "Vertices within this great-circle distance (km) of the site centre get DEM heights; " *
                       "the rest stay at 0 m. 50 km = the edge of triangulation.h5's ring zone; larger values also " *
                       "give the sparse far-field vertices (~77 km apart) real heights"
            arg_type = Float64
            default  = 50.0
    end
    return parse_args(s)
end

args = parse_commandline()

# --- 1. The outline: four corner points, or a KML/KMZ placemark ---
corners = args["corners"]
if !isempty(corners)
    (!isempty(args["kml"]) || !isempty(args["placemark"]) || args["list"]) &&
        error("--corners replaces --kml, --placemark and --list; give one or the other")
    latlons = [(corners[2k - 1], corners[2k]) for k in 1:4]
    println("\nOutline from --corners (lat, lon): ", join(("($la, $lo)" for (la, lo) in latlons), " → "))
    outline = outline_from_corners(latlons, "box")
else
    kml_path = isempty(args["kml"]) ? joinpath(RESOURCES, "tambito_candidates_june23.kml") : args["kml"]
    println("\nReading KML: $kml_path")
    doc = read_kml(kml_path)
    if args["list"]
        list_placemarks(stdout, doc)
        exit(0)
    end
    outline = select_outline(doc, args["placemark"])
end
nverts = sum(length(p[1]) for p in outline.polygons)
nholes = sum(length(p) - 1 for p in outline.polygons)
println("  Outline \"$(outline.label)\": $(length(outline.polygons)) polygon(s), $nverts outer vertices, $nholes hole(s)")
longlat0_deg = area_centroid(outline)
println("  Centre (area centroid): lon=$(longlat0_deg[1])°  lat=$(longlat0_deg[2])°")

terrain_r_km = args["terrain-radius-km"]
lon_min, lon_max, lat_min, lat_max = circle_extent_deg(longlat0_deg, terrain_r_km)
(lon_min < -180 || lon_max > 180) && error("the $(terrain_r_km) km terrain circle crosses the ±180° meridian, which is not supported")
args["dem"] == "copernicus" && max(abs(lat_min), abs(lat_max)) > COPERNICUS_MAX_LAT &&
    error("the $(terrain_r_km) km terrain circle reaches latitude $(round(max(abs(lat_min), abs(lat_max)), digits=2))°; " *
          "Copernicus tiles above $(COPERNICUS_MAX_LAT)° are not supported (use --dem with an HDF5 grid)" *
          (isempty(corners) ? "" : ". Check that --corners was given as LAT LON pairs, not LON LAT"))

groupname = !isempty(args["name"]) ? args["name"] :
            !isempty(corners) ? "box_$(round(longlat0_deg[2], digits=4))_$(round(longlat0_deg[1], digits=4))" :
            replace(outline.label, r"[^A-Za-z0-9_.-]+" => "_")
outdir = args["outdir"]; mkpath(outdir)
h5_path     = joinpath(outdir, "$(groupname).h5")
g_path      = joinpath(outdir, "$(groupname).jld2")
terrain_ply = joinpath(outdir, "$(groupname)_terrain.ply")
obs_ply     = joinpath(outdir, "$(groupname)_obs_surface.ply")

# --- 2. Load the base triangulation and check the outline fits its fine zone ---
println("\nLoading base triangulation: $(args["triangulation"])")
tri_file, tri_group = rsplit(args["triangulation"], ":"; limit=2)
verts_deg, faces = h5open(tri_file) do f
    g = f[tri_group]
    Float64.(read(g["vertices"])), Int.(read(g["faces"]))
end
r_cap, r_ring = zone_radii_km(verts_deg)
extent = outline_extent_km(outline, longlat0_deg)
println("  Vertices: $(size(verts_deg, 1))  Faces: $(size(faces, 1))  " *
        "zones: fine < $(round(r_cap, digits=1)) km, ring < $(round(r_ring, digits=1)) km")
println("  Outline reaches $(round(extent, digits=2)) km from its centre")

# Warnings are shown when raised and repeated at the end of the run, so they are not lost in the output.
run_warnings = String[]
warn!(msg) = (push!(run_warnings, msg); @warn msg)
extent > r_cap && warn!("The outline reaches $(round(extent, digits=1)) km from its centre, beyond the fine-mesh " *
    "zone (r < $(round(r_cap, digits=1)) km). Part of the detector region will sit on coarser triangles " *
    "(~$(round(sqrt((r_ring^2 - r_cap^2) / r_cap^2), digits=1))× larger); the detector-region check below gives the " *
    "affected area. To avoid it, keep every point of the outline within $(round(r_cap, digits=1)) km of its centre " *
    "(e.g. split it into smaller sites).")
extent > r_ring && warn!("The outline extends past $(round(r_ring, digits=1)) km, where the base triangulation " *
    "has essentially no terrain (vertices tens of km apart).")
extent > terrain_r_km && warn!("The outline extends past --terrain-radius-km = $terrain_r_km km; vertices beyond it " *
    "get no DEM height.")

# Outside the fine-mesh zone needs an explicit go-ahead: ask, or stop when no one can answer
# (batch jobs, stdin from /dev/null) unless --allow-outside-fine-mesh was given.
if extent > r_cap
    if args["allow-outside-fine-mesh"]
        println("  Continuing outside the fine-mesh zone (--allow-outside-fine-mesh)")
    else
        print("\nThe detector outline extends outside the fine-mesh zone (r < $(round(r_cap, digits=1)) km). " *
              "Continue anyway? [y/N]: ")
        flush(stdout)
        answer = eof(stdin) ? "" : lowercase(strip(readline(stdin)))
        if answer in ("y", "yes")
            println("  Continuing outside the fine-mesh zone (confirmed)")
        else
            println(isempty(answer) ? "\nNo answer (no interactive input)." : "Stopped.")
            println("Nothing was written. Shrink or split the outline so it stays within $(round(r_cap, digits=1)) km " *
                    "of its centre, or re-run with --allow-outside-fine-mesh to build it anyway.")
            exit(1)
        end
    end
end

# --- 3. Rotate and apply elevation ---
println("\nRotating triangulation and applying DEM elevation ($(args["dem"]))...")
R = PREM_RADII_KM[end] * 1000.0
tile_dir = isempty(args["tile-dir"]) ? nothing : args["tile-dir"]
ecef, n_dem = build_ecef_vertices(verts_deg, longlat0_deg, terrain_r_km, args["dem"], R; tile_dir=tile_dir)
println("  Vertices with DEM elevation: $n_dem / $(size(ecef, 1))")

# --- 4. Fix face orientation and build the detector region ---
println("\nFixing mesh orientation and computing detector region...")
# All face normals must point away from the Earth's centre (validate_triangle); flip the
# winding of any that do not rather than dropping them, so the full global mesh is kept.
fixed_faces = copy(faces); n_flipped = 0
for i in axes(fixed_faces, 1)
    v0, v1, v2 = (ecef[fixed_faces[i, k], :] for k in 1:3)
    if dot(cross(v1 - v0, v2 - v0), (v0 + v1 + v2) / 3) < 0
        fixed_faces[i, 2], fixed_faces[i, 3] = fixed_faces[i, 3], fixed_faces[i, 2]
        global n_flipped += 1
    end
end
n_flipped > 0 && println("  Flipped $(n_flipped) inward-facing faces")

detector_indices = Int[]
for i in axes(fixed_faces, 1)
    lon_d, lat_d = rad2deg.(cart_to_longlat(vec(mean(ecef[fixed_faces[i, :], :], dims=1))...))
    inside(outline, lon_d, lat_d) && push!(detector_indices, i)
end
isempty(detector_indices) && error("no mesh triangle has its centre inside the outline — the outline is smaller " *
                                   "than the triangles there, or lies outside the mesh's terrain")
face_edges(i) = [norm(ecef[fixed_faces[i, a], :] - ecef[fixed_faces[i, b], :]) for (a, b) in ((1, 2), (2, 3), (3, 1))]
face_area(i) = norm(cross(ecef[fixed_faces[i, 2], :] - ecef[fixed_faces[i, 1], :],
                          ecef[fixed_faces[i, 3], :] - ecef[fixed_faces[i, 1], :])) / 2
println("  Total faces: $(size(fixed_faces, 1))  Detector faces: $(length(detector_indices))  " *
        "(median edge $(round(median(reduce(vcat, face_edges.(detector_indices))), digits=1)) m, " *
        "surface area $(round(sum(face_area, detector_indices) / 1e6, digits=3)) km²)")

# Fine-zone check on the actual detector triangles: a face is outside the fine mesh if any of its
# vertices lies beyond r_cap (great-circle distance from the site centre).
centre_u = longlat_to_cart(deg2rad.(longlat0_deg)...)
vertex_km(v) = 6371.0 * acos(clamp(dot(ecef[v, :] ./ norm(ecef[v, :]), centre_u), -1.0, 1.0))
coarse = filter(i -> any(vertex_km(fixed_faces[i, k]) > r_cap for k in 1:3), detector_indices)
if !isempty(coarse)
    fine = setdiff(detector_indices, coarse)
    a_coarse = sum(face_area, coarse); a_all = sum(face_area, detector_indices)
    edge_fine = isempty(fine) ? NaN : median(reduce(vcat, face_edges.(fine)))
    warn!("$(length(coarse)) of $(length(detector_indices)) detector triangles " *
          "($(round(100 * a_coarse / a_all, digits=1))% of the detector surface area, $(round(a_coarse / 1e6, digits=3)) km²) " *
          "lie outside the fine-mesh zone (r < $(round(r_cap, digits=1)) km). Median edge there: " *
          "$(round(median(reduce(vcat, face_edges.(coarse))), digits=0)) m, vs $(round(edge_fine, digits=0)) m inside.")
else
    println("  Detector region lies entirely inside the fine-mesh zone (r < $(round(r_cap, digits=1)) km)")
end

# --- 5. Build GCD bundle and save JLD2 (full outward-facing mesh, no radius crop) ---
println("\nBuilding GCD bundle and saving to JLD2...")
longlat_rad = (deg2rad(longlat0_deg[1]), deg2rad(longlat0_deg[2]))
prem_radii = PREM_RADII_KM .* 1_000.0 .* u"m"
frames = TamboSim.build_gcd_bundle(ecef, fixed_faces, longlat_rad, prem_radii, detector_indices)
save_frames(g_path, frames, streams=('G', 'C', 'D'))
println("  Saved → $g_path ($(round(filesize(g_path) / 1024^2, digits=1)) MB)")

frames2 = load_frames(g_path)
println("  Reloaded — PREM layers: $(length(frames2.g_frames[end]["prem"]))  " *
        "triangles: $(length(frames2.g_frames[end]["topography"]))  " *
        "detector faces: $(length(frames2.d_frames[end]["detector_region"]))")

g_frame = frames.g_frames[end]
d_frame = frames.d_frames[end]

# --- 6. HDF5 export (derived) ---
TamboSim.dump_to_h5(g_frame, d_frame, h5_path, groupname)
println("HDF5: wrote $h5_path:$groupname")

# --- 7. Binary PLYs for CORSIKA ---
# The terrain PLY is the full closed mesh, as run_corsika writes it by default (no
# max_radius_km). A radius crop + watertight skirt is fragile here: dump_to_ply keeps faces by
# centroid distance, and a crop near the triangulation's ring edge (~50 km), where long fan
# triangles join the far field, can leave pinch vertices that make_watertight rejects.
println("\nWriting CORSIKA PLY files...")
TamboSim.dump_to_ply(g_frame, terrain_ply)
println("Terrain PLY (full closed mesh): wrote $terrain_ply")
TamboSim.dump_to_ply(d_frame, obs_ply)
println("Obs surface PLY: wrote $obs_ply")

println("\nAll geometry files written to $outdir")
if !isempty(run_warnings)
    println("\n", "="^80, "\n$(length(run_warnings)) WARNING(S) for \"$(outline.label)\" — check before using this geometry:")
    foreach(((k, w),) -> println("  $k. ", w), enumerate(run_warnings))
    println("="^80)
end
