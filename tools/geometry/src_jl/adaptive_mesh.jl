# adaptive_mesh.jl — a site-adaptive base triangulation (functions only; included by create_geometry.jl after
# kml_outline.jl and site_mesh.jl).
#
# The base triangulations in triangulation.h5 put their fine points in a cap within 10 km of the site centre. A
# site-adaptive one puts them where the detector is instead: within --fine-border-km of the outline(s), however the
# sites are spread inside the 50 km ring. Densities come from the base triangulation, so triangle sizes match it:
#
#   fine region   cap density (e.g. ~320 points/km² for _100000: ~60 m triangles), uniform random points
#   rest of ring  ring density (~13/km²: ~300 m); the base's own ring points, plus new ones where its cap was
#   beyond ring   the base's own far-field points, unchanged
#
# and the points are joined by a spherical Delaunay triangulation, as Kiara Carloni's were with GMT sphtriangulate:
# the Delaunay triangulation of their stereographic projection, which reproduces the GMT faces of
# base_triangulation_100000 exactly (all but the 7 around the antipode, where a fan closes the mesh instead). The
# result is in the base's north-pole frame, so the builder rotates it onto the site as usual.

using DelaunayTriangulation
using Random

const ADAPTIVE_MESH_SEED = 20261126        # fixed: the same outline and border give the same mesh
const FINE_REGION_CELL_KM = 0.05           # raster for the fine region (points are ~56 m apart there)

"""
    spherical_delaunay(U) -> faces (M×3)

Delaunay triangulation of unit vectors `U` (n×3, none at (0, 0, -1)): the planar Delaunay triangulation of their
stereographic projection from (0, 0, -1), closed by a fan of triangles to an extra vertex n + 1 at (0, 0, -1).
"""
function spherical_delaunay(U::AbstractMatrix{Float64}; rng=Xoshiro(ADAPTIVE_MESH_SEED))
    n = size(U, 1)
    pts = [(U[i, 1] / (1 + U[i, 3]), U[i, 2] / (1 + U[i, 3])) for i in 1:n]
    tri = triangulate(pts; randomise=true, rng=rng)
    faces = [collect(DelaunayTriangulation.triangle_vertices(T)) for T in DelaunayTriangulation.each_solid_triangle(tri)]
    hull = DelaunayTriangulation.get_convex_hull_vertices(tri)          # closed: first == last
    for k in 1:length(hull)-1
        push!(faces, [hull[k + 1], hull[k], n + 1])
    end
    permutedims(reduce(hcat, faces))
end

unitvec(lon, lat) = [cosd(lat) * cosd(lon), cosd(lat) * sind(lon), sind(lat)]
lonlat(u) = (atand(u[2], u[1]), asind(clamp(u[3] / sqrt(sum(abs2, u)), -1, 1)))

"Azimuthal equidistant projection about `centre` = (lon, lat) in degrees: (x east, y north) in km."
function aeqd(centre, lon, lat)
    u = unitvec(lon, lat); c = unitvec(centre...)
    east = [-sind(centre[1]), cosd(centre[1]), 0.0]; north = cross(c, east)
    d = 6371.0 * acos(clamp(dot(u, c), -1.0, 1.0))
    t = [dot(u, east), dot(u, north)]; s = sqrt(sum(abs2, t))
    s == 0 ? (0.0, 0.0) : (d * t[1] / s, d * t[2] / s)
end

"Inverse of `aeqd`: (lon, lat) in degrees of the point (x east, y north) km from `centre`."
function aeqd_inv(centre, x, y)
    c = unitvec(centre...); east = [-sind(centre[1]), cosd(centre[1]), 0.0]; north = cross(c, east)
    ρ = hypot(x, y); ρ == 0 && return centre
    a = ρ / 6371.0
    lonlat(cos(a) .* c .+ sin(a) .* (x / ρ .* east .+ y / ρ .* north))
end

"Squared Euclidean distance transform of a line (Felzenszwalb & Huttenlocher), ignoring infinite entries."
function edt1d(f::AbstractVector{Float64})
    n = length(f); d = fill(Inf, n)
    v = Int[]; z = Float64[]
    for q in 1:n
        isfinite(f[q]) || continue
        s = -Inf
        while !isempty(v)
            p = v[end]
            s = ((f[q] + q^2) - (f[p] + p^2)) / (2q - 2p)
            (length(v) > 1 && s <= z[end]) ? (pop!(v); pop!(z)) : break
        end
        push!(v, q); push!(z, isempty(z) ? -Inf : s)
    end
    isempty(v) && return d
    k = 1
    for q in 1:n
        while k < length(v) && z[k + 1] < q
            k += 1
        end
        d[q] = (q - v[k])^2 + f[v[k]]
    end
    d
end

"""
    fine_region(outline, centre, border_km) -> (; x0, y0, h, mask)

Raster (azimuthal equidistant km about `centre`, cells of `h` km, cell (i, j) centred at
(x0 + (i - 0.5)h, y0 + (j - 0.5)h)) of the ground inside the outline or within `border_km` of it.
"""
function fine_region(outline::Outline, centre, border_km; h=FINE_REGION_CELL_KM)
    rings = [[[aeqd(centre, q...) for q in ring] for ring in p] for p in outline.polygons]
    xs = [q[1] for p in rings for q in p[1]]; ys = [q[2] for p in rings for q in p[1]]
    pad = border_km + 2h
    x0 = minimum(xs) - pad; y0 = minimum(ys) - pad
    nx = ceil(Int, (maximum(xs) + pad - x0) / h); ny = ceil(Int, (maximum(ys) + pad - y0) / h)
    inside = falses(nx, ny)
    for p in rings                                    # scanline fill, even-odd over each polygon's rings
        row = falses(nx)
        for j in 1:ny
            yc = y0 + (j - 0.5) * h
            xc = Float64[]
            for ring in p, k in eachindex(ring)
                (xa, ya), (xb, yb) = ring[k], ring[mod1(k + 1, length(ring))]
                (ya > yc) != (yb > yc) && push!(xc, xa + (yc - ya) * (xb - xa) / (yb - ya))
            end
            sort!(xc)
            for k in 1:2:length(xc)-1
                i1 = max(1, ceil(Int, (xc[k] - x0) / h + 0.5)); i2 = min(nx, floor(Int, (xc[k + 1] - x0) / h + 0.5))
                i1 <= i2 && (inside[i1:i2, j] .= true)
            end
        end
    end
    any(inside) || error("the outline covers no $(1000h) m cell of the fine-region raster")
    f = [inside[i, j] ? 0.0 : Inf for i in 1:nx, j in 1:ny]
    for j in 1:ny; f[:, j] = edt1d(f[:, j]); end
    for i in 1:nx; f[i, :] = edt1d(f[i, :]); end
    (; x0, y0, h, mask=sqrt.(f) .* h .<= border_km)
end

in_region(r, x, y) = (i = floor(Int, (x - r.x0) / r.h) + 1; j = floor(Int, (y - r.y0) / r.h) + 1;
                      1 <= i <= size(r.mask, 1) && 1 <= j <= size(r.mask, 2) && r.mask[i, j])

"Area (km²) of a spherical cap of great-circle radius `r` km on the 6371 km sphere."
cap_area(r) = 2π * 6371.0^2 * (1 - cos(r / 6371.0))

"""
    adaptive_triangulation(tri, outline, centre, border_km) -> NamedTuple

A site-adaptive version of the base triangulation `tri` (from `load_triangulation`) for `outline`, whose bundle is
centred on `centre` = (lon, lat): its fine density within `border_km` of the outline (clipped 1 km inside the ring
edge), its ring density elsewhere in the ring, and its far-field points beyond. Returns
`(; verts_deg, faces, fine, n_fine, fine_area_km2, clipped, ρ_fine, ρ_ring)`: vertices (lon, lat in degrees, north-pole frame, as
in triangulation.h5), faces, which vertices are fine-region points, and whether the ring edge cut the region.
"""
function adaptive_triangulation(tri, outline::Outline, centre, border_km)
    rng = Xoshiro(ADAPTIVE_MESH_SEED)
    rot = Matrix(site_rotation(deg2rad.(centre)))                  # north-pole frame → site
    d = pole_distance_km(tri.verts_deg)
    ρ_fine = count(d .<= tri.r_cap) / cap_area(tri.r_cap)
    ρ_ring = count(tri.r_cap .< d .<= tri.r_ring) / (cap_area(tri.r_ring) - cap_area(tri.r_cap))
    limit = tri.r_ring - 1.0

    region = fine_region(outline, centre, border_km)
    n_before = count(region.mask)
    cells = Tuple{Float64,Float64}[]                               # fine-region cells, cleared beyond the limit
    for j in axes(region.mask, 2), i in axes(region.mask, 1)
        region.mask[i, j] || continue
        x = region.x0 + (i - 0.5) * region.h; y = region.y0 + (j - 0.5) * region.h
        hypot(x, y) <= limit ? push!(cells, (x, y)) : (region.mask[i, j] = false)
    end
    clipped = length(cells) < n_before
    area = length(cells) * region.h^2

    # fine points: uniform over the region's cells
    n_fine = round(Int, ρ_fine * area)
    pole = rot'                                                     # site → north-pole frame
    to_pole(lon, lat) = pole * unitvec(lon, lat)
    U = Vector{Vector{Float64}}(undef, 0); sizehint!(U, n_fine + count(d .> tri.r_cap) + 10_000)
    for _ in 1:n_fine
        x, y = cells[rand(rng, 1:length(cells))]
        push!(U, to_pole(aeqd_inv(centre, x + (rand(rng) - 0.5) * region.h, y + (rand(rng) - 0.5) * region.h)...))
    end
    infine(u) = (ll = lonlat(rot * u); in_region(region, aeqd(centre, ll...)...))

    # ring density elsewhere within the ring: the base's ring points, and new ones where its cap was
    zc = cos(tri.r_cap / 6371.0); n_cap = round(Int, ρ_ring * cap_area(tri.r_cap))
    for _ in 1:n_cap
        z = zc + (1 - zc) * rand(rng); φ = 2π * rand(rng); s = sqrt(1 - z^2)
        u = [s * cos(φ), s * sin(φ), z]
        infine(u) || push!(U, u)
    end
    for i in findall(tri.r_cap .< d .<= tri.r_ring)
        u = unitvec(tri.verts_deg[i, 1], tri.verts_deg[i, 2])
        infine(u) || push!(U, u)
    end
    # far field: unchanged
    for i in findall(d .> tri.r_ring)
        push!(U, unitvec(tri.verts_deg[i, 1], tri.verts_deg[i, 2]))
    end

    Um = permutedims(reduce(hcat, U))
    faces = spherical_delaunay(Um; rng=rng)
    verts_deg = Matrix{Float64}(undef, size(Um, 1) + 1, 2)
    for i in axes(Um, 1)
        verts_deg[i, 1], verts_deg[i, 2] = lonlat(view(Um, i, :))
    end
    verts_deg[end, :] .= (0.0, -90.0)                              # the fan's vertex at the antipode
    fine = falses(size(verts_deg, 1)); fine[1:n_fine] .= true
    (; verts_deg, faces, fine, n_fine, fine_area_km2=area, clipped, ρ_fine, ρ_ring)
end
