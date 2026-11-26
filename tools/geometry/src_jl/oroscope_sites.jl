# oroscope_sites.jl — candidate detector sites around a point, from an oroscope search (functions only; included
# by create_geometry.jl after copernicus_dem.jl, kml_outline.jl and site_mesh.jl).
#
# oroscope (https://github.com/mbustama/oroscope) is Python; it runs as a subprocess through
# src_py/oroscope_search.py. The interpreter is the tools' own CondaPkg environment (tools/CondaPkg.toml:
# Python + oroscope, installed on first use into ~/.julia/conda_environments/tambosim_tools), unless
# --python / $OROSCOPE_PYTHON names another one that has oroscope. The search DEM is Copernicus GLO-30,
# written here as a GeoTIFF covering the search circle plus the scan's ray range; candidate detector pixels
# are kept inside the circle. Each site oroscope selects becomes an Outline that traces its mask pixels
# exactly (staircase edges, holes kept), labelled A, B, C, … best first (oroscope's capacity order).

using ArchGDAL
using CondaPkg
using JSON3

const OROSCOPE_DRIVER = normpath(joinpath(@__DIR__, "..", "src_py", "oroscope_search.py"))

"Site letters: A … Z, then AA, AB, …"
site_letter(k::Integer) = k <= 26 ? string('A' + k - 1) : site_letter((k - 1) ÷ 26) * string('A' + (k - 1) % 26)

const CONDAPKG_SHARED_ENV = "@tambosim_tools"

"""
The Python interpreter to run oroscope with: `python` if given, else the tools' CondaPkg environment, created or
updated from tools/CondaPkg.toml as needed (the first time downloads Python and oroscope: a few minutes).
The environment is shared (~/.julia/conda_environments/tambosim_tools), not kept in the code tree, unless a
CondaPkg environment or backend is already chosen through JULIA_CONDAPKG_ENV / JULIA_CONDAPKG_BACKEND.
"""
function oroscope_python(python::AbstractString)
    if !isempty(python)
        Sys.which(python) === nothing && !isfile(python) && error("Python interpreter \"$python\" (--python / " *
            "\$OROSCOPE_PYTHON) not found; leave it unset to use the tools' own Python environment")
        return python
    end
    haskey(ENV, "JULIA_CONDAPKG_ENV") || haskey(ENV, "JULIA_CONDAPKG_BACKEND") ||
        (ENV["JULIA_CONDAPKG_ENV"] = CONDAPKG_SHARED_ENV)
    println("  Checking the Python environment for oroscope (CondaPkg; the first run installs it, a few minutes)...")
    CondaPkg.resolve()
    exe = CondaPkg.which("python")
    exe === nothing && error("CondaPkg environment has no python; see tools/CondaPkg.toml")
    exe
end

"Run the oroscope driver (output goes to the terminal); stop with a pointer to that output if it fails."
function run_oroscope_driver(python::AbstractString, args::Vector{String})
    flush(stdout)
    p = run(ignorestatus(`$python $OROSCOPE_DRIVER $args`))
    p.exitcode == 0 || error("the oroscope search failed (exit code $(p.exitcode)); see its output above")
    nothing
end

"How far (km) oroscope's arrival scan traces rays for this configuration, plus the oroscope version."
function oroscope_plan(python, config)
    out = tempname() * ".json"
    try
        run_oroscope_driver(python, ["plan", "--config", config, "--out", out])
        plan = JSON3.read(read(out, String))
        return Float64(plan.walk_km), String(plan.oroscope_version)
    finally
        rm(out; force=true)
    end
end

"Write a GridInterp (cell-centre lon/lat grid) as a north-up EPSG:4326 GeoTIFF, as oroscope reads it."
function write_dem_geotiff(path, g::GridInterp)
    nx, ny = size(g.z)
    A = Float32.(g.z[:, end:-1:1])                                     # [column, row], row 1 = north
    gt = [g.lon0 - g.dlon / 2, g.dlon, 0.0, g.lat0 + (ny - 0.5) * g.dlat, 0.0, -g.dlat]   # NW corner of the NW cell
    ArchGDAL.create(path; driver=ArchGDAL.getdriver("GTiff"), width=nx, height=ny, nbands=1, dtype=Float32) do ds
        ArchGDAL.write!(ds, A, 1)
        ArchGDAL.setgeotransform!(ds, gt)
        ArchGDAL.setproj!(ds, ArchGDAL.toWKT(ArchGDAL.importEPSG(4326)))
    end
    path
end

"""
Boundary rings of the pixels where `mask[c, r]` is true (c = column west → east, r = row north → south), as
vertex lists on the pixel-corner lattice (x = c - 1 … c, y = r - 1 … r). Outer boundaries have positive
signed area in (x, y), holes negative. Where two pixels touch only at a corner the ring turns to keep them
apart (4-connectivity, as oroscope's labelling).
"""
function pixel_rings(mask::AbstractMatrix{Bool})
    nc, nr = size(mask)
    isin(c, r) = 1 <= c <= nc && 1 <= r <= nr && mask[c, r]
    V = Tuple{Int,Int}
    out = Dict{V,Vector{V}}()                                   # lattice vertex => outgoing edge directions
    add!(v, d) = push!(get!(() -> V[], out, v), d)
    for r in 1:nr, c in 1:nc                                    # region on the right of every edge (y down)
        mask[c, r] || continue
        x, y = c - 1, r - 1
        isin(c, r - 1) || add!((x, y), (1, 0))
        isin(c + 1, r) || add!((x + 1, y), (0, 1))
        isin(c, r + 1) || add!((x + 1, y + 1), (-1, 0))
        isin(c - 1, r) || add!((x, y + 1), (0, -1))
    end
    used = Set{Tuple{V,V}}(); rings = Vector{Vector{V}}()
    for (v0, ds) in out, d0 in ds
        (v0, d0) in used && continue
        ring = V[]; v, d = v0, d0
        while true
            push!(used, (v, d)); push!(ring, v)
            v = v .+ d
            opts = out[v]
            dn = length(opts) == 1 ? only(opts) : (-d[2], d[1])        # corner contact: turn right
            dn in opts || error("pixel_rings: inconsistent boundary at $v")
            (v, dn) == (v0, d0) && break
            d = dn
        end
        push!(rings, drop_collinear(ring))
    end
    rings
end

"Remove the vertices of a unit-step lattice ring that lie on a straight run."
function drop_collinear(ring)
    n = length(ring)
    ring[[ring[i] .- ring[mod1(i - 1, n)] != ring[mod1(i + 1, n)] .- ring[i] for i in 1:n]]
end

lattice_area(ring) = sum(ring[i][1] * ring[mod1(i + 1, length(ring))][2] - ring[mod1(i + 1, length(ring))][1] * ring[i][2]
                         for i in eachindex(ring)) / 2

"""
    site_outline(mask, label, x0, y0, west, north, step) -> Outline

Outline of the pixels where `mask` is true; `mask` covers lattice columns x0 … and rows y0 … of a grid whose NW
corner is (west, north) with square pixels of `step` degrees.
"""
function site_outline(mask::AbstractMatrix{Bool}, label, x0, y0, west, north, step)
    rings = pixel_rings(mask)
    outers = filter(r -> lattice_area(r) > 0, rings); holes = filter(r -> lattice_area(r) < 0, rings)
    flt(r) = LonLat[(Float64(p[1]), Float64(p[2])) for p in r]
    lonlat(r) = LonLat[(west + (x0 + p[1]) * step, north - (y0 + p[2]) * step) for p in r]
    polys = [[lonlat(o)] for o in outers]
    for h in holes
        # The pixel on the region side of the hole's first edge is inside the outer ring that holds the hole.
        d = sign.(h[2] .- h[1])
        probe = (h[1][1] + 0.5 * d[1] - 0.5 * d[2], h[1][2] + 0.5 * d[2] + 0.5 * d[1])
        k = findfirst(o -> in_ring(flt(o), probe...), outers)
        k === nothing && error("site $label: hole not inside any outer boundary")
        push!(polys[k], lonlat(h))
    end
    Outline(label, polys)
end

"""
A point well inside the site, to put its label: the centre (lon, lat) of the most interior pixel (last to
survive repeated erosion of `mask`, which covers columns x0 + 1 … and rows y0 + 1 …), nearest the site's mean.
"""
function label_anchor(mask::AbstractMatrix{Bool}, x0, y0, west, north, step)
    idx = findall(mask); mc = mean(first.(Tuple.(idx))); mr = mean(last.(Tuple.(idx)))
    m = copy(mask)
    while true
        e = [m[c, r] && (c > 1 && m[c-1, r]) && (c < size(m, 1) && m[c+1, r]) && (r > 1 && m[c, r-1]) &&
             (r < size(m, 2) && m[c, r+1]) for c in axes(m, 1), r in axes(m, 2)]
        any(e) || break
        m = e
    end
    core = Tuple.(findall(m))
    c, r = core[argmin([(p[1] - mc)^2 + (p[2] - mr)^2 for p in core])]
    (west + (x0 + c - 0.5) * step, north - (y0 + r - 0.5) * step)
end

xml_escape(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
kml_coords(ring) = join(("$(round(lo, digits=8)),$(round(la, digits=8)),0" for (lo, la) in [ring; ring[1:1]]), " ")

sites_kml_title(radius_km, lat, lon) = "oroscope sites within $(radius_km) km of ($lat, $lon)"

"""
One outline holding all of `outlines` (their polygons together), labelled by their joined labels, e.g. "BD": the
detector region of a bundle built for several sites at once.
"""
combine_outlines(outlines) = Outline(join(o.label for o in outlines), reduce(vcat, [o.polygons for o in outlines]))

"Summary of several oroscope site records built as one detector region."
combined_summary(labels, sites) = "Sites $(join(labels, " + ")) combined: $(round(sum(s.area_km2 for s in sites), digits=2)) km², " *
                                  "$(sum(s.capacity_exact for s in sites)) units"

"One-line summary of an oroscope site record."
function site_summary(s)
    score = haskey(s, :arrival_scan) && haskey(s.arrival_scan, :score_p50) ? ", median score $(round(s.arrival_scan.score_p50, digits=2))" : ""
    "$(s.area_km2) km², $(s.capacity_exact) units ($(s.grid_type)), faces $(s.facing_direction)$score"
end

"""
Write outlines as a KML, one placemark each, named by its label (A, B, …), with `descriptions` as their text,
so any of them can be rebuilt with --kml.
"""
function write_sites_kml(path, outlines, descriptions; title)
    open(path, "w") do io
        println(io, """<?xml version="1.0" encoding="UTF-8"?>
            <kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>$(xml_escape(title))</name>
            <Style id="site"><LineStyle><color>ff00ffff</color><width>2</width></LineStyle><PolyStyle><color>4000ffff</color></PolyStyle></Style>""")
        for (o, d) in zip(outlines, descriptions)
            print(io, "<Placemark><name>$(o.label)</name><description>$(xml_escape(d))</description>",
                  "<styleUrl>#site</styleUrl>", length(o.polygons) > 1 ? "<MultiGeometry>" : "")
            for p in o.polygons
                print(io, "<Polygon><outerBoundaryIs><LinearRing><coordinates>", kml_coords(p[1]),
                      "</coordinates></LinearRing></outerBoundaryIs>")
                for h in p[2:end]
                    print(io, "<innerBoundaryIs><LinearRing><coordinates>", kml_coords(h), "</coordinates></LinearRing></innerBoundaryIs>")
                end
                print(io, "</Polygon>")
            end
            println(io, length(o.polygons) > 1 ? "</MultiGeometry>" : "", "</Placemark>")
        end
        println(io, "</Document></kml>")
    end
    path
end

"""
    oroscope_search(python, config, centre, radius_km; outdir, stem, tile_dir) -> NamedTuple

Run oroscope (with `python`, or the tools' own environment if empty) with `config` (JSON) for detector sites within `radius_km` of `centre` = (lon, lat), on Copernicus
GLO-30. Its outputs go to `<outdir>/<stem>_oroscope/`; the candidates are written to `<outdir>/<stem>_sites.kml`.
Returns `(; sites, outlines, anchors, dem, kml, rundir, n_unselected, walk_km)`: oroscope's records (best first),
the matching Outlines (labelled A, B, …), a point inside each site, the search DEM, and how far the scan traces rays.
"""
function oroscope_search(python, config, centre, radius_km; outdir, stem, tile_dir)
    lon, lat = centre
    python = oroscope_python(python)
    walk_km, version = oroscope_plan(python, config)
    println("  oroscope $version ($python); its arrival scan traces rays $(round(walk_km, digits=2)) km")
    reach_km = radius_km + walk_km + 1.0
    lo0, lo1, la0, la1 = circle_extent_deg(centre, reach_km)
    max(abs(la0), abs(la1)) > COPERNICUS_MAX_LAT &&
        error("the search reaches latitude $(round(max(abs(la0), abs(la1)), digits=2))°; Copernicus tiles above " *
              "$(COPERNICUS_MAX_LAT)° are not supported")
    (lo0 < -180 || lo1 > 180) && error("the search area crosses the ±180° meridian, which is not supported")

    println("\nSearch DEM: Copernicus GLO-30 within $(round(reach_km, digits=1)) km of the point")
    grid_lons = range(lo0, lo1; length=max(2, ceil(Int, (lo1 - lo0) / 0.25) + 1))
    grid_lats = range(la0, la1; length=max(2, ceil(Int, (la1 - la0) / 0.25) + 1))
    dem = copernicus_interp([lo for lo in grid_lons for _ in grid_lats], [la for _ in grid_lons for la in grid_lats];
                            tile_dir=tile_dir, margin=0.0)
    rundir = joinpath(outdir, "$(stem)_oroscope"); mkpath(rundir)
    dem_tif = write_dem_geotiff(joinpath(rundir, "search_dem.tif"), dem)
    println("  $(size(dem.z, 1)) × $(size(dem.z, 2)) cells → $dem_tif")

    println("\nRunning oroscope ($config) for sites within $(radius_km) km of ($lat, $lon)...\n")
    try
        run_oroscope_driver(python, ["scan", "--config", abspath(config), "--dem", abspath(dem_tif),
                                     "--lat", string(lat), "--lon", string(lon), "--radius-km", string(radius_km),
                                     "--outdir", abspath(rundir)])
    finally
        rm(dem_tif; force=true); rm(replace(dem_tif, r"\.tif$" => ".npy"); force=true)   # + oroscope's cache
    end

    info = JSON3.read(read(joinpath(rundir, "sites.json"), String))
    sites = collect(info.sites)
    g = info.grid
    L = Matrix{Int32}(undef, g.cols, g.rows)                              # L[column, row], row 1 = north
    read!(joinpath(rundir, "site_labels.bin"), L)
    ENDIAN_BOM == 0x04030201 || (L .= bswap.(L))
    pixels = [Tuple{Int,Int}[] for _ in sites]
    for r in axes(L, 2), c in axes(L, 1)
        L[c, r] > 0 && push!(pixels[L[c, r]], (c, r))
    end
    outlines = Outline[]; anchors = LonLat[]
    for (k, px) in enumerate(pixels)
        isempty(px) && error("oroscope site $(sites[k].site_id) has no pixels in the label raster")
        c0, c1 = extrema(first.(px)); r0, r1 = extrema(last.(px))
        mask = falses(c1 - c0 + 1, r1 - r0 + 1)
        for (c, r) in px
            mask[c - c0 + 1, r - r0 + 1] = true
        end
        push!(outlines, site_outline(mask, site_letter(k), c0 - 1, r0 - 1, g.west, g.north, g.step_deg))
        push!(anchors, label_anchor(mask, c0 - 1, r0 - 1, g.west, g.north, g.step_deg))
    end
    rm(joinpath(rundir, "site_labels.bin"))                     # read; the sites KML keeps the exact outlines
    kml = joinpath(outdir, "$(stem)_sites.kml")
    isempty(outlines) || write_sites_kml(kml, outlines, site_summary.(sites); title=sites_kml_title(radius_km, lat, lon))
    (; sites, outlines, anchors, dem, kml, rundir, n_unselected=Int(info.n_qualifying_unselected), walk_km)
end
