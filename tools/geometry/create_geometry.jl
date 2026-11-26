# create_geometry.jl
#
# Build a TamboSim geometry bundle for a site outlined in a KML/KMZ file (any source: Google
# Earth Pro or web, QGIS, …), for a box of four corners, or for sites found by an oroscope search
# around a point. Rotates a north-pole-centred base triangulation onto the outline's area centroid,
# gives it DEM heights (Copernicus GLO-30 by default), and writes:
#
#   <name>.jld2                Self-contained G, C, D bundle (D = detector region inside the outline);
#                              all the simulation needs
#
# and, on request:
#
#   --h5:  <name>.h5           The same geometry as plain arrays (schema of
#                              examples/templates/1_create_geometry.jl), to rebuild the .jld2 with
#                              build_gcd_bundle if a TamboSim type change makes it unloadable
#   --ply: <name>_terrain.ply, <name>_obs_surface.ply
#                              CORSIKA meshes, for inspection; run_corsika writes its own from the .jld2
#
#   julia --project=tools tools/geometry/create_geometry.jl --kml my_site.kmz [--placemark NAME]
#   julia --project=tools tools/geometry/create_geometry.jl --kml my_site.kml --list
#   julia --project=tools tools/geometry/create_geometry.jl --corners LAT1 LON1 LAT2 LON2 LAT3 LON3 LAT4 LON4
#   julia --project=tools tools/geometry/create_geometry.jl --point LAT LON --radius-km 10 \
#       --oroscope-config tools/geometry/oroscope_configs/tambo_colca_config.json
#
# Add --view to look at the result in an interactive 3D window (TamboMakie + GLMakie) at the end.
#
# The outline is a KML placemark, selected by its name, id or "Comments" field (optional when the
# file has a single polygon placemark; all its Polygons form the outline, holes excluded); a box
# given by --corners (four lat/lon points in order around it); or, with --point, sites found by
# oroscope (https://github.com/mbustama/oroscope; Python, installed automatically on first use) within
# --radius-km of the point using the criteria in --oroscope-config. The candidates are written to
# <name>_sites.kml (placemarks A, B, …, best first) and shown in an interactive map to pick from
# (or chosen with --sites A,C); each site picked is built as its own bundle, <name>_<letter>.jld2, or, with
# --combine (or the map's "one bundle" box), all of them as one bundle <name>_<letters>.jld2 with a combined
# detector region.
# One of --kml, --corners or --point is required. The default base triangulation is
# resources/triangulation.h5:base_triangulation_100000 (the TAMBITO one); the TAMBITO candidate
# outlines are in resources/tambito_candidates_june23.kml.
#
# Triangle sizes come entirely from the base triangulation (see README.md); the DEM only sets
# vertex heights. Its fine triangles fill a 10 km cap around the centre; with --fine-border-km B a
# site-adaptive triangulation puts them within B km of the outline(s) instead, anywhere in the 50 km
# ring (src_jl/adaptive_mesh.jl). --point does this by default, with B = the oroscope ray range.
# Vertices within --terrain-radius-km (great-circle distance, default 50 km = the triangulation's
# ring edge) of the centre get DEM heights; the rest stay on the 6371 km sphere at 0 m.
#
# Fixes relative to the pre-2026-11 version of this script (bundles built before then are affected):
#   1. DEM registration. Pixel-registered GMT grids come out of GMT.jl with n+1 cell EDGES; the
#      old script kept the first n, putting every value at its cell's SW corner, so all terrain was
#      drawn 7.5″ (≈ 230 m) S and W of its true position (≈ 6″ net for SRTM15+, see README.md).
#   2. DEM source. Copernicus GLO-30 (1″) replaces SRTM15+ (15″) by default; bilinear point
#      sampling replaces the Dierckx spline (impractical on a 1″ grid).
#   3. Site centre. The old vertex mean counted the KML ring's closing vertex twice (~220 m bias
#      for west of Huambo); the centre is now the polygon's area centroid.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using LinearAlgebra
using Statistics
using Unitful
using TamboSim

include(joinpath(@__DIR__, "src_jl", "copernicus_dem.jl"))
include(joinpath(@__DIR__, "src_jl", "kml_outline.jl"))
include(joinpath(@__DIR__, "src_jl", "site_mesh.jl"))
include(joinpath(@__DIR__, "src_jl", "oroscope_sites.jl"))
include(joinpath(@__DIR__, "src_jl", "adaptive_mesh.jl"))

const RESOURCES = joinpath(@__DIR__, "resources")
const PREM_RADII_KM = [1221.5, 3480.0, 3630.0, 5600.0, 5701.0, 5771.0,
                       5971.0, 6151.0, 6291.0, 6346.6, 6356.0, 6368.0, 6371.0]
const COPERNICUS_MAX_LAT = 50.0   # GLO-30 tiles change longitude spacing above 50°

function parse_commandline()
    s = ArgParseSettings(description = "Build a TamboSim geometry bundle from a KML/KMZ outline, four corner " *
                                       "points, or an oroscope site search around a point + DEM + base triangulation")
    @add_arg_table! s begin
        "--kml"
            help     = "KML or KMZ file with the site outline(s); this, --corners or --point is required"
            arg_type = String
            default  = ""
        "--corners"
            help     = "Instead of a KML: four corners of the detector box as LAT LON pairs in degrees, " *
                       "in order around the box (either direction), e.g. --corners -15.757 -72.123 " *
                       "-15.745 -72.138 -15.740 -72.134 -15.752 -72.119"
            nargs    = 8
            arg_type = Float64
            metavar  = "LAT/LON"
        "--point"
            help     = "Instead of an outline: search for detector sites around this point (LAT LON in degrees) " *
                       "with oroscope, pick from the candidates in an interactive map, and build each one picked"
            nargs    = 2
            arg_type = Float64
            metavar  = "LAT/LON"
        "--radius-km"
            help     = "--point: search radius (km); candidate detector ground must lie within it"
            arg_type = Float64
            default  = 10.0
        "--oroscope-config"
            help     = "--point: oroscope JSON configuration with the site criteria, e.g. " *
                       "tools/geometry/oroscope_configs/tambo_colca_config.json (its dem_path, origin and road map are replaced)"
            arg_type = String
            default  = ""
        "--sites"
            help     = "--point: build these candidates without opening the map, e.g. A,C or all"
            arg_type = String
            default  = ""
        "--combine"
            help     = "--point: build the chosen sites as one bundle, centred on all of them, with one combined " *
                       "detector region (they must fit in one fine-mesh zone), instead of one bundle per site"
            action   = :store_true
        "--python"
            help     = "--point: use this Python interpreter (with oroscope installed) instead of the tools' own " *
                       "environment, which is created automatically on first use (default: \$OROSCOPE_PYTHON if set)"
            arg_type = String
            default  = get(ENV, "OROSCOPE_PYTHON", "")
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
        "--view"
            help     = "After building, open an interactive 3D window (GLMakie, via TamboMakie) of the terrain " *
                       "and detector region; the script ends when it is closed"
            action   = :store_true
        "--h5"
            help     = "Also write <name>.h5: the geometry as plain arrays, to rebuild the .jld2 if a TamboSim " *
                       "type change makes it unloadable"
            action   = :store_true
        "--ply"
            help     = "Also write the CORSIKA terrain and observation-surface PLYs (run_corsika makes its own " *
                       "from the .jld2; these are for inspection)"
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
            help     = "Output file stem (default: the placemark's name/id, box_<lat>_<lon> of the centre for " *
                       "--corners, site_<lat>_<lon> of the point for --point)"
            arg_type = String
            default  = ""
        "--outdir", "-o"
            help     = "Output directory (default: the directory the script is run from)"
            arg_type = String
            default  = "."
        "--fine-border-km"
            help     = "Site-adaptive mesh: fine triangles (the base triangulation's cap density, ~60 m for _100000) " *
                       "within this distance (km) of the outline(s) wherever they are in the 50 km ring, its ring " *
                       "density (~300 m) elsewhere; \"cap\" for the base's own 10 km fine cap around the centre. " *
                       "Default: with --point, the oroscope scan's ray range (e.g. max_dist_km), so the fine " *
                       "mesh covers the far wall the array looks at; otherwise the cap"
            arg_type = String
            default  = ""
        "--terrain-radius-km"
            help     = "Vertices within this great-circle distance (km) of the site centre get DEM heights; " *
                       "the rest stay at 0 m. 50 km = the edge of triangulation.h5's ring zone; larger values also " *
                       "give the sparse far-field vertices (~77 km apart) real heights"
            arg_type = Float64
            default  = 50.0
    end
    return parse_args(s)
end

"""
    fine_border_km(args; walk_km=nothing) -> Float64 or nothing

The site-adaptive mesh's border (km) around the outline, or `nothing` for the base triangulation's fine cap:
--fine-border-km as given ("cap" → nothing); by default the oroscope scan's ray range `walk_km` with
--point, else the cap.
"""
function fine_border_km(args; walk_km=nothing)
    s = strip(args["fine-border-km"])
    s == "cap" && return nothing
    isempty(s) && return walk_km
    b = tryparse(Float64, s)
    (b === nothing || b < 0) && error("--fine-border-km takes a distance in km (≥ 0) or \"cap\", not \"$s\"")
    b
end

"""
How far (km) from a bundle's centre its detector outline can reach on fine triangles: the base triangulation's cap
radius, or for a site-adaptive mesh (`border` in km) 1 km inside its ring's edge.
"""
fine_limit_km(tri, border) = border === nothing ? tri.r_cap : tri.r_ring - 1.0

"Short description of that limit, for the site listing and map."
fine_limit_desc(tri, border) = (border === nothing ? "fine mesh" : "site-adaptive fine mesh") *
                               " < $(round(fine_limit_km(tri, border), digits=2)) km"

"What the fine mesh covers, for the site map and 3D view."
fine_mesh_desc(tri, border) = border === nothing ? "within $(round(tri.r_cap, digits=1)) km of the bundle centre" :
                                                   "within $(round(border, digits=1)) km of the sites"

"Base triangulation from path.h5:group, with its fine-zone and ring radii (km)."
function load_triangulation(spec)
    println("\nLoading base triangulation: $spec")
    tri_file, tri_group = rsplit(spec, ":"; limit=2)
    verts_deg, faces = h5open(tri_file) do f
        g = f[tri_group]
        Float64.(read(g["vertices"])), Int.(read(g["faces"]))
    end
    r_cap, r_ring = zone_radii_km(verts_deg)
    println("  Vertices: $(size(verts_deg, 1))  Faces: $(size(faces, 1))  " *
            "zones: fine < $(round(r_cap, digits=1)) km, ring < $(round(r_ring, digits=1)) km")
    (; verts_deg, faces, r_cap, r_ring)
end

"""
    build_site(outline, groupname, tri, args; outdir, tile_dir, border=nothing, confirmed=false) -> NamedTuple or nothing

Build and save the bundle for one outline. Returns `(; label, g_path, d_frame, extent, warnings)`, or `nothing`
when the outline leaves the fine-mesh zone and the build is not confirmed (`confirmed` = already confirmed,
e.g. in the site picker).
"""
function build_site(outline, groupname, tri, args; outdir, tile_dir, border=nothing, confirmed=false)
    println("\n", "─"^80, "\nBuilding \"$(outline.label)\" → $(groupname).jld2")
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
              (isempty(args["corners"]) ? "" : ". Check that --corners was given as LAT LON pairs, not LON LAT"))

    h5_path     = joinpath(outdir, "$(groupname).h5")
    g_path      = joinpath(outdir, "$(groupname).jld2")
    terrain_ply = joinpath(outdir, "$(groupname)_terrain.ply")
    obs_ply     = joinpath(outdir, "$(groupname)_obs_surface.ply")

    # --- Check the outline fits where the mesh can be fine: the base's cap, or (site-adaptive) the ring ---
    r_cap, r_ring = tri.r_cap, tri.r_ring
    adaptive = border !== nothing
    fine_limit = fine_limit_km(tri, border)
    zone = adaptive ? "the part of the ring where the site-adaptive fine mesh can go (r < $(round(fine_limit, digits=1)) km)" :
                      "the fine-mesh zone (r < $(round(r_cap, digits=1)) km)"
    extent = outline_extent_km(outline, longlat0_deg)
    println("  Outline reaches $(round(extent, digits=2)) km from its centre")

    # Warnings are shown when raised and repeated at the end of the run, so they are not lost in the output.
    run_warnings = String[]
    warn!(msg) = (push!(run_warnings, msg); @warn msg)
    extent > fine_limit && warn!("The outline reaches $(round(extent, digits=1)) km from its centre, beyond $zone. " *
        "Part of the detector region will sit on coarser triangles " *
        "(~$(round(sqrt((r_ring^2 - r_cap^2) / r_cap^2), digits=1))× larger); the detector-region check below gives the " *
        "affected area. To avoid it, keep every point of the outline within $(round(fine_limit, digits=1)) km of its centre " *
        "(e.g. split it into smaller sites" * (adaptive ? ")." : ", or use --fine-border-km)."))
    extent > r_ring && warn!("The outline extends past $(round(r_ring, digits=1)) km, where the base triangulation " *
        "has essentially no terrain (vertices tens of km apart).")
    extent > terrain_r_km && warn!("The outline extends past --terrain-radius-km = $terrain_r_km km; vertices beyond it " *
        "get no DEM height.")

    # Outside the fine-mesh zone needs an explicit go-ahead: ask, or stop when no one can answer
    # (batch jobs, stdin from /dev/null) unless --allow-outside-fine-mesh was given.
    if extent > fine_limit
        if args["allow-outside-fine-mesh"] || confirmed
            println("  Continuing outside $zone ($(confirmed ? "picked in the site map" : "--allow-outside-fine-mesh"))")
        else
            print("\nThe detector outline extends outside $zone. Continue anyway? [y/N]: ")
            flush(stdout)
            answer = eof(stdin) ? "" : lowercase(strip(readline(stdin)))
            if answer in ("y", "yes")
                println("  Continuing outside the fine-mesh zone (confirmed)")
            else
                println(isempty(answer) ? "\nNo answer (no interactive input)." : "Stopped.")
                println("\"$(outline.label)\" was not built. Shrink or split the outline so it stays within " *
                        "$(round(fine_limit, digits=1)) km of its centre" * (adaptive ? "" : " (or use --fine-border-km)") *
                        ", or re-run with --allow-outside-fine-mesh to build it anyway.")
                return nothing
            end
        end
    end

    # --- The mesh: the base triangulation, or a site-adaptive one with its fine points around the outline ---
    if adaptive
        println("\nBuilding a site-adaptive triangulation: fine within $(border) km of the outline...")
        t = @elapsed m = adaptive_triangulation(tri, outline, longlat0_deg, border)
        println("  Fine region $(round(m.fine_area_km2, digits=1)) km²: $(m.n_fine) fine points " *
                "($(round(m.ρ_fine, digits=1))/km², ring $(round(m.ρ_ring, digits=2))/km²); " *
                "$(size(m.verts_deg, 1)) vertices, $(size(m.faces, 1)) faces ($(round(t, digits=1)) s)")
        m.clipped && warn!("The fine region (outline + $(border) km) reaches past $(round(fine_limit, digits=1)) km from " *
                           "the centre, 1 km inside the ring's edge; it was cut there.")
        verts_deg, faces, fine_vertex = m.verts_deg, m.faces, m.fine
    else
        verts_deg, faces = tri.verts_deg, tri.faces
        fine_vertex = pole_distance_km(verts_deg) .<= r_cap
    end

    # --- Rotate and apply elevation ---
    println("\nRotating triangulation and applying DEM elevation ($(args["dem"]))...")
    R = PREM_RADII_KM[end] * 1000.0
    ecef, n_dem = build_ecef_vertices(verts_deg, longlat0_deg, terrain_r_km, args["dem"], R; tile_dir=tile_dir)
    println("  Vertices with DEM elevation: $n_dem / $(size(ecef, 1))")

    # --- Fix face orientation and build the detector region ---
    println("\nFixing mesh orientation and computing detector region...")
    # All face normals must point away from the Earth's centre (validate_triangle); flip the
    # winding of any that do not rather than dropping them, so the full global mesh is kept.
    fixed_faces = copy(faces); n_flipped = 0
    for i in axes(fixed_faces, 1)
        v0, v1, v2 = (ecef[fixed_faces[i, k], :] for k in 1:3)
        if dot(cross(v1 - v0, v2 - v0), (v0 + v1 + v2) / 3) < 0
            fixed_faces[i, 2], fixed_faces[i, 3] = fixed_faces[i, 3], fixed_faces[i, 2]
            n_flipped += 1
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

    # Fine-mesh check on the actual detector triangles: a face is coarse if any of its vertices is not a fine
    # point (beyond r_cap of the centre for the base triangulation; outside the fine region for an adaptive one).
    coarse = filter(i -> !all(fine_vertex[fixed_faces[i, k]] for k in 1:3), detector_indices)
    if !isempty(coarse)
        fine = setdiff(detector_indices, coarse)
        a_coarse = sum(face_area, coarse); a_all = sum(face_area, detector_indices)
        edge_fine = isempty(fine) ? NaN : median(reduce(vcat, face_edges.(fine)))
        warn!("$(length(coarse)) of $(length(detector_indices)) detector triangles " *
              "($(round(100 * a_coarse / a_all, digits=1))% of the detector surface area, $(round(a_coarse / 1e6, digits=3)) km²) " *
              "have a vertex outside $(adaptive ? "the site-adaptive fine region" : "the fine-mesh zone (r < $(round(r_cap, digits=1)) km)"). Median edge there: " *
              "$(round(median(reduce(vcat, face_edges.(coarse))), digits=0)) m, vs $(round(edge_fine, digits=0)) m inside.")
    else
        println("  Detector region lies entirely in the fine mesh" *
                (adaptive ? " (site-adaptive, $(border) km border)" : " (r < $(round(r_cap, digits=1)) km)"))
    end

    # --- Build GCD bundle and save JLD2 (full outward-facing mesh, no radius crop) ---
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

    # --- Optional HDF5 export (plain arrays; rebuilds the .jld2 via build_gcd_bundle) ---
    if args["h5"]
        TamboSim.dump_to_h5(g_frame, d_frame, h5_path, groupname)
        println("HDF5: wrote $h5_path:$groupname")
    end

    # --- Optional binary PLYs for CORSIKA ---
    # The terrain PLY is the full closed mesh, as run_corsika writes it by default (no
    # max_radius_km). A radius crop + watertight skirt is fragile here: dump_to_ply keeps faces by
    # centroid distance, and a crop near the triangulation's ring edge (~50 km), where long fan
    # triangles join the far field, can leave pinch vertices that make_watertight rejects.
    if args["ply"]
        println("\nWriting CORSIKA PLY files...")
        TamboSim.dump_to_ply(g_frame, terrain_ply)
        println("Terrain PLY (full closed mesh): wrote $terrain_ply")
        TamboSim.dump_to_ply(d_frame, obs_ply)
        println("Obs surface PLY: wrote $obs_ply")
    end
    fine_faces = findall(i -> all(fine_vertex[fixed_faces[i, k]] for k in 1:3), axes(fixed_faces, 1))
    (; label=outline.label, g_path, d_frame=frames2.d_frames[end], extent, warnings=run_warnings, fine_faces,
     fine_reach=adaptive ? extent + border : r_cap, fine_desc=fine_mesh_desc(tri, border))
end

"""
Candidate sites from an oroscope search around --point, and the ones to build: picked in the site map, or
listed with --sites. Returns a vector of (outline, groupname, confirmed) and the fine-mesh border (km, or nothing
for the base's cap), which by default follows the oroscope scan's ray range.
"""
function oroscope_targets(args, tri; outdir, tile_dir)
    lat, lon = args["point"]
    -90 <= lat <= 90 && -180 <= lon <= 180 || error("--point $lat $lon is out of range (give LAT LON in degrees)")
    radius_km = args["radius-km"]
    radius_km > 0 || error("--radius-km must be positive")
    config = args["oroscope-config"]
    isempty(config) && error("--point needs --oroscope-config: an oroscope JSON configuration with the site criteria " *
                             "(e.g. $(joinpath(@__DIR__, "oroscope_configs", "tambo_colca_config.json")))")
    isfile(config) || error("oroscope config not found: $config")
    stem = !isempty(args["name"]) ? args["name"] : "site_$(round(lat, digits=4))_$(round(lon, digits=4))"

    println("\nSearching for sites with oroscope")
    search = oroscope_search(args["python"], config, (lon, lat), radius_km; outdir=outdir, stem=stem, tile_dir=tile_dir)
    if isempty(search.outlines)
        println("\noroscope found no site within $(radius_km) km of ($lat, $lon) that meets the criteria in $config " *
                "(its explanation above says which cut removed them; its outputs are in $(search.rundir)). Nothing was built.")
        exit(1)
    end
    extents = [outline_extent_km(o, area_centroid(o)) for o in search.outlines]
    border = fine_border_km(args; walk_km=search.walk_km)
    limit, limit_desc = fine_limit_km(tri, border), fine_limit_desc(tri, border)
    println("\n", "="^80, "\noroscope found $(length(search.outlines)) candidate site(s) within $(radius_km) km " *
            "(outlines in $(search.kml); oroscope's outputs in $(search.rundir)):")
    for (k, o) in enumerate(search.outlines)
        far = extents[k] > limit ? "  ⚠ beyond the $limit_desc" : ""
        println("  $(rpad(o.label, 3)) $(site_summary(search.sites[k])); reaches $(round(extents[k], digits=2)) km from its centre$far")
    end
    search.n_unselected > 0 && println("  ($(search.n_unselected) more qualified but were not selected by oroscope, " *
                                       "e.g. because of stop_at_target)")
    println("Fine mesh: ", border === nothing ? "the base triangulation's cap, $(fine_mesh_desc(tri, border)) (--fine-border-km cap)" :
            "site-adaptive, $(fine_mesh_desc(tri, border))" *
            (isempty(strip(args["fine-border-km"])) ? " (oroscope's ray range; set it with --fine-border-km)" : ""))
    println("="^80)

    letters = [o.label for o in search.outlines]
    if !isempty(args["sites"])
        want = uppercase.(strip.(split(args["sites"], ",")))
        chosen = want == ["ALL"] ? collect(eachindex(letters)) :
                 [something(findfirst(==(w), letters), 0) for w in want]
        any(==(0), chosen) && error("--sites $(args["sites"]): unknown site(s) $(join(want[chosen .== 0], ", ")); " *
                                    "the candidates are $(join(letters, ", "))")
        confirmed = false; combine = args["combine"]
    else
        println("\nOpening the site map (GLMakie): select the sites to build, then press \"Build selected\" or Enter...")
        include(joinpath(@__DIR__, "src_jl", "select_sites.jl"))
        chosen, combine = Base.invokelatest(pick_sites, search, (lon, lat), radius_km, extents, limit;
                                            combine=args["combine"], limit_desc=limit_desc,
                                            mesh_desc=fine_mesh_desc(tri, border))
        confirmed = true
    end
    if isempty(chosen)
        println("\nNo site selected; nothing was built. To build one later without searching again: " *
                "--kml $(search.kml) --placemark <letter> --name $(stem)_<letter>")
        exit(0)
    end
    chosen = unique(chosen)
    if combine && length(chosen) > 1
        # One bundle: all chosen sites form one outline (and detector region); it is added to the sites KML so the
        # bundle can be rebuilt with --kml … --placemark <letters>.
        o = combine_outlines(search.outlines[chosen])
        outlines = [search.outlines; o]
        write_sites_kml(search.kml, outlines, [site_summary.(search.sites); combined_summary(letters[chosen], search.sites[chosen])];
                        title=sites_kml_title(radius_km, lat, lon))
        println("\nBuilding sites $(join(letters[chosen], ", ")) as one bundle (\"$(o.label)\", added to $(search.kml))")
        return [(o, "$(stem)_$(o.label)", confirmed)], border
    end
    println("\nBuilding site(s) $(join(letters[chosen], ", "))")
    [(search.outlines[k], "$(stem)_$(letters[k])", confirmed) for k in chosen], border
end

function main()
    args = parse_commandline()
    modes = [m for (m, given) in (("--kml", !isempty(args["kml"])), ("--corners", !isempty(args["corners"])),
                                  ("--point", !isempty(args["point"]))) if given]
    isempty(modes) && error("no outline given: pass --kml FILE (KML or KMZ), --corners LAT1 LON1 … LAT4 LON4, or " *
                            "--point LAT LON with --oroscope-config")
    length(modes) > 1 && error("$(join(modes, " and ")) are alternatives; give one")
    !isempty(args["kml"]) || (isempty(args["placemark"]) && !args["list"]) ||
        error("--placemark and --list need --kml")

    if args["list"]
        println("\nReading KML: $(args["kml"])")
        list_placemarks(stdout, read_kml(args["kml"]))
        exit(0)
    end
    outdir = args["outdir"]; mkpath(outdir)
    # --point reads the DEM tiles twice (search, then each bundle): share one temporary tile cache.
    tile_dir = !isempty(args["tile-dir"]) ? args["tile-dir"] : !isempty(args["point"]) ? mktempdir() : nothing
    isempty(args["tile-dir"]) && tile_dir !== nothing && atexit(() -> rm(tile_dir; recursive=true, force=true))
    tri = load_triangulation(args["triangulation"])

    border = fine_border_km(args)                      # --point: replaced by the search's default below
    if !isempty(args["point"])
        targets, border = oroscope_targets(args, tri; outdir=outdir, tile_dir=tile_dir)
    elseif !isempty(args["corners"])
        corners = args["corners"]
        latlons = [(corners[2k - 1], corners[2k]) for k in 1:4]
        println("\nOutline from --corners (lat, lon): ", join(("($la, $lo)" for (la, lo) in latlons), " → "))
        outline = outline_from_corners(latlons, "box")
        c = area_centroid(outline)
        name = !isempty(args["name"]) ? args["name"] : "box_$(round(c[2], digits=4))_$(round(c[1], digits=4))"
        targets = [(outline, name, false)]
    else
        println("\nReading KML: $(args["kml"])")
        outline = select_outline(read_kml(args["kml"]), args["placemark"])
        name = !isempty(args["name"]) ? args["name"] : replace(outline.label, r"[^A-Za-z0-9_.-]+" => "_")
        targets = [(outline, name, false)]
    end

    built = []
    for (outline, name, confirmed) in targets
        b = build_site(outline, name, tri, args; outdir=outdir, tile_dir=tile_dir, border=border, confirmed=confirmed)
        b === nothing || push!(built, b)
    end

    println("\n", "─"^80)
    isempty(built) && (println("Nothing was built."); exit(1))
    println("Geometry written to $(abspath(outdir)): ", join((basename(b.g_path) for b in built), ", "))
    for b in built
        isempty(b.warnings) && continue
        println("\n", "="^80, "\n$(length(b.warnings)) WARNING(S) for \"$(b.label)\" ($(basename(b.g_path))) — check before using this geometry:")
        foreach(((k, w),) -> println("  $k. ", w), enumerate(b.warnings))
        println("="^80)
    end
    length(built) < length(targets) && println("\n$(length(targets) - length(built)) of $(length(targets)) site(s) were not built (see above).")

    # --- Optional interactive view (loads GLMakie + TamboMakie only when asked), one window per bundle ---
    if args["view"]
        println("\nLoading the 3D viewer (GLMakie)...")
        include(joinpath(@__DIR__, "src_jl", "view_geometry.jl"))
        for b in built
            # the outline plus some surroundings, and the whole fine-mesh region
            view_side_km = max(10.0, ceil(2.5 * b.extent), ceil(2 * b.fine_reach + 1))
            Base.invokelatest(view_geometry, b.d_frame; side_km=view_side_km,
                              title="$(b.label): $(basename(b.g_path))", fine_faces=b.fine_faces, fine_desc=b.fine_desc)
        end
    end
end

main()
