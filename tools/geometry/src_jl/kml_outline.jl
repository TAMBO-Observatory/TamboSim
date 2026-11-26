# kml_outline.jl — the detector outline, from a KML/KMZ file or from corner points (functions only; included by
# create_geometry.jl).
#
# A placemark is selected by its `id` attribute, its <name>, or its "Comments" field
# (ExtendedData SimpleData/Data named "Comments", or whose Schema displayName is "Comments", as
# in Google Earth web exports). Its geometry must contain at least one Polygon; all Polygons in
# it (e.g. a MultiGeometry) form the outline, and inner boundaries are holes.

using EzXML
using Statistics
using p7zip_jll

const LonLat = Tuple{Float64,Float64}

"A detector outline: one or more polygons, each a vector of rings (outer first, then holes)."
struct Outline
    label::String
    polygons::Vector{Vector{Vector{LonLat}}}
end

"Parse a KML file, or the main document (doc.kml, else the first .kml) inside a KMZ archive."
function read_kml(path::AbstractString)
    isfile(path) || error("KML file not found: $path")
    lowercase(splitext(path)[2]) == ".kmz" || return EzXML.readxml(path)
    dir = mktempdir()
    try
        run(pipeline(`$(p7zip()) x $path -o$dir -y`, stdout=devnull, stderr=devnull))
        kmls = [joinpath(r, f) for (r, _, fs) in walkdir(dir) for f in fs if endswith(lowercase(f), ".kml")]
        isempty(kmls) && error("$path contains no .kml document")
        return EzXML.readxml(kmls[something(findfirst(p -> basename(p) == "doc.kml", kmls), 1)])
    finally
        rm(dir; recursive=true, force=true)
    end
end

# All queries match on local-name(), so no namespaces are registered. (EzXML's default registers
# the node's in-scope ones, and warns on every query about KML's empty-prefix default namespace.)
const NO_NAMESPACES = Pair{String,String}[]
xpfind(path, node) = EzXML.findall(path, node, NO_NAMESPACES)
xpfirst(path, node) = EzXML.findfirst(path, node, NO_NAMESPACES)
child_text(node, name) = (c = xpfirst("./*[local-name()='$name']", node); c === nothing ? "" : strip(EzXML.nodecontent(c)))

"Schema field name → displayName (Google Earth web renames fields, e.g. COL5B9A… → Comments)."
function schema_display_names(doc)
    names = Dict{String,String}()
    for f in xpfind("//*[local-name()='SimpleField']", EzXML.root(doc))
        haskey(f, "name") || continue
        dn = child_text(f, "displayName")
        names[f["name"]] = isempty(dn) ? f["name"] : dn
    end
    names
end

"Parse a KML <coordinates> string into (lon, lat) pairs (altitude ignored)."
function parse_coordinates(text::AbstractString)
    pts = LonLat[]
    for tup in split(strip(text))
        parts = split(tup, ",")
        length(parts) >= 2 || error("malformed KML coordinate tuple \"$tup\"")
        push!(pts, (parse(Float64, parts[1]), parse(Float64, parts[2])))
    end
    pts
end

"Drop the ring's closing duplicate vertex and check it is a real polygon ring."
function open_ring(pts::Vector{LonLat}, what)
    ring = (length(pts) > 1 && pts[end] == pts[1]) ? pts[1:end-1] : pts
    length(unique(ring)) >= 3 || error("$what has fewer than 3 distinct vertices")
    ring
end

"Everything needed to identify and use one Placemark."
function placemark_info(pm, display_names)
    comments = ""
    for d in xpfind(".//*[local-name()='SimpleData' or local-name()='Data']", pm)
        haskey(d, "name") || continue
        if get(display_names, d["name"], d["name"]) == "Comments"
            v = xpfirst("./*[local-name()='value']", d)          # <Data><value>…</value></Data>
            comments = strip(EzXML.nodecontent(v === nothing ? d : v))
        end
    end
    polys = xpfind(".//*[local-name()='Polygon']", pm)
    geoms = xpfind(".//*[local-name()='Point' or local-name()='LineString' or local-name()='LinearRing' or " *
                   "local-name()='Polygon' or local-name()='Model' or local-name()='Track']", pm)
    kind = isempty(polys) ? (isempty(geoms) ? "no geometry" : EzXML.nodename(first(geoms))) :
           length(polys) == 1 ? "Polygon" : "$(length(polys)) Polygons"
    (node=pm, id=haskey(pm, "id") ? pm["id"] : "", name=child_text(pm, "name"), comments=comments,
     polygons=polys, kind=kind)
end

placemarks(doc) = (dn = schema_display_names(doc);
                   [placemark_info(pm, dn) for pm in xpfind("//*[local-name()='Placemark']", EzXML.root(doc))])

"Print a table of the placemarks in a KML document."
function list_placemarks(io::IO, doc)
    infos = placemarks(doc)
    println(io, "$(length(infos)) placemark(s); select one with --placemark <id | name | Comments>:")
    for p in infos
        println(io, "  [", p.kind, "]  id=\"", p.id, "\"  name=\"", p.name, "\"",
                isempty(p.comments) ? "" : "  Comments=\"$(first(p.comments, 60))\"")
    end
end

label(p) = !isempty(p.name) ? p.name : !isempty(p.id) ? p.id : !isempty(p.comments) ? p.comments : "placemark"

"""
    select_outline(doc, key) -> Outline

The polygon outline of the placemark whose id, name or Comments equals `key`. With an empty
`key` the document must contain exactly one placemark with a Polygon.
"""
function select_outline(doc, key::AbstractString)
    infos = placemarks(doc)
    listing = sprint(list_placemarks, doc)
    if isempty(key)
        cands = filter(p -> !isempty(p.polygons), infos)
        length(cands) == 1 || error("the KML has $(length(cands)) placemarks with polygons; choose one with --placemark.\n$listing")
        p = only(cands)
    else
        cands = filter(p -> key in (p.id, p.name, p.comments), infos)
        isempty(cands) && error("no placemark with id, name or Comments \"$key\".\n$listing")
        if length(cands) > 1                       # e.g. a pin and an outline sharing a name
            withpoly = filter(p -> !isempty(p.polygons), cands)
            length(withpoly) == 1 ||
                error("\"$key\" matches $(length(cands)) placemarks; select one by its id.\n$listing")
            cands = withpoly
        end
        p = only(cands)
        isempty(p.polygons) && error("placemark \"$key\" is a $(p.kind); the detector outline must be a Polygon")
    end
    polys = map(enumerate(p.polygons)) do (k, poly)
        outer = xpfirst("./*[local-name()='outerBoundaryIs']//*[local-name()='coordinates']", poly)
        outer === nothing && error("polygon $k of \"$(label(p))\" has no outer boundary")
        rings = [open_ring(parse_coordinates(EzXML.nodecontent(outer)), "outer boundary of polygon $k")]
        for (h, inner) in enumerate(xpfind("./*[local-name()='innerBoundaryIs']//*[local-name()='coordinates']", poly))
            push!(rings, open_ring(parse_coordinates(EzXML.nodecontent(inner)), "hole $h of polygon $k"))
        end
        rings
    end
    for poly in polys, ring in poly
        lons = first.(ring)
        maximum(lons) - minimum(lons) > 180 && error("outline crosses the ±180° meridian, which is not supported")
    end
    Outline(label(p), polys)
end

orient(a, b, c) = sign((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]))
"Do segments p1–p2 and q1–q2 cross (properly, not just touch)?"
segments_cross(p1, p2, q1, q2) = orient(p1, p2, q1) * orient(p1, p2, q2) < 0 && orient(q1, q2, p1) * orient(q1, q2, p2) < 0

"""
    outline_from_corners(latlons, label) -> Outline

Outline from corner points given as (lat, lon) pairs in degrees, in order around the boundary
(either direction) — e.g. the four corners of a box. Rejects out-of-range values, repeated or
collinear corners, and corners listed diagonally (a self-crossing "bow-tie").
"""
function outline_from_corners(latlons, label::AbstractString)
    length(latlons) >= 3 || error("need at least 3 corners")
    for (lat, lon) in latlons
        -90 <= lat <= 90   || error("latitude $lat is out of range (corners are LAT LON pairs)")
        -180 <= lon <= 180 || error("longitude $lon is out of range (corners are LAT LON pairs)")
    end
    ring = LonLat[(Float64(lon), Float64(lat)) for (lat, lon) in latlons]
    length(unique(ring)) == length(ring) || error("corners must be distinct")
    maximum(first.(ring)) - minimum(first.(ring)) > 180 && error("the box crosses the ±180° meridian, which is not supported")
    n = length(ring)
    # collinear first (relative to the box's size), so near-zero orientations don't read as crossings
    lon0, lat0 = ring[1]
    twice_area = sum((ring[i][1] - lon0) * (ring[mod1(i + 1, n)][2] - lat0) -
                     (ring[mod1(i + 1, n)][1] - lon0) * (ring[i][2] - lat0) for i in 1:n)
    span2 = (maximum(first.(ring)) - minimum(first.(ring)))^2 + (maximum(last.(ring)) - minimum(last.(ring)))^2
    abs(twice_area) > 1e-9 * span2 || error("the corners lie on a line (the box has no area)")
    for i in 1:n, j in i+2:n
        (i == 1 && j == n) && continue                       # adjacent through the wrap-around
        segments_cross(ring[i], ring[mod1(i + 1, n)], ring[j], ring[mod1(j + 1, n)]) &&
            error("corner edges $(i)–$(mod1(i + 1, n)) and $(j)–$(mod1(j + 1, n)) cross: give the corners in order " *
                  "around the box, not diagonally")
    end
    Outline(label, [[ring]])
end

"Ray-casting point-in-ring test in degree lon/lat space (ring without closing duplicate)."
function in_ring(ring::Vector{LonLat}, lon::Real, lat::Real)
    inside = false; j = length(ring)
    for i in eachindex(ring)
        xi, yi = ring[i]; xj, yj = ring[j]
        ((yi > lat) != (yj > lat)) && (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) && (inside = !inside)
        j = i
    end
    inside
end

"Inside any polygon's outer boundary and outside its holes."
inside(o::Outline, lon::Real, lat::Real) =
    any(p -> in_ring(p[1], lon, lat) && !any(h -> in_ring(h, lon, lat), p[2:end]), o.polygons)

"""
Area-weighted centroid (lon, lat) of the outline (holes subtracted), computed on a local
equirectangular projection — independent of how densely each side is digitised.
"""
function area_centroid(o::Outline)
    allv = reduce(vcat, [p[1] for p in o.polygons])
    lon0, lat0 = mean(first.(allv)), mean(last.(allv)); kx = cosd(lat0)
    A = 0.0; cx = 0.0; cy = 0.0
    for p in o.polygons, (k, ring) in enumerate(p)
        x = [(q[1] - lon0) * kx for q in ring]; y = [q[2] - lat0 for q in ring]
        a = 0.0; sx = 0.0; sy = 0.0
        for i in eachindex(ring)
            j = mod1(i + 1, length(ring)); c = x[i]*y[j] - x[j]*y[i]
            a += c; sx += (x[i] + x[j]) * c; sy += (y[i] + y[j]) * c
        end
        a /= 2; s = (k == 1 ? 1 : -1) * sign(a)            # outer adds, holes subtract, any winding
        A += s * a; cx += s * sx / 6; cy += s * sy / 6
    end
    (lon0 + cx / A / kx, lat0 + cy / A)
end

"Largest great-circle distance (km, 6371 km sphere) from `centre` to any outline vertex."
function outline_extent_km(o::Outline, centre)
    u(lon, lat) = (cosd(lat)*cosd(lon), cosd(lat)*sind(lon), sind(lat))
    c = u(centre...)
    maximum(6371.0 * acos(clamp(sum(u(q...) .* c), -1.0, 1.0)) for p in o.polygons for q in p[1])
end
