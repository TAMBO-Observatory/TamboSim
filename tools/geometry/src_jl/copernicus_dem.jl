# copernicus_dem.jl — elevation sources for the geometry tools (included, not run).
#
# Everything here returns a `GridInterp`: a regular, ascending lon/lat grid of cell-CENTRE
# heights, interpolated bilinearly. Vertex heights are point samples of that grid; tested
# against a drone survey at west_of_huambo this beats box means sized to the mesh spacing
# both near the array (60 m facets) and in the 10–50 km ring (~300 m facets).
#
# Sources
#   "copernicus"  Copernicus GLO-30 (1″ ≈ 30 m, EGM2008 heights, surface model incl. buildings and
#                 vegetation; ocean = 0 m). 1° tiles from the public AWS bucket, fetched into a
#                 temporary directory that is deleted after reading, or cached in `tile_dir`.
#                 Recommended: correctly registered (≈ 2 m vs drone/AW3D30) and fine enough
#                 that the triangulation, not the DEM, limits the mesh.
#   path.h5       A grid with `longitude`, `latitude`, `elevation[n_lat, n_lon]`, e.g. GMT's
#                 earth_relief_15s (SRTM15+) written from GMT.jl. Pixel-registered GMT grids carry
#                 n+1 cell EDGES; they are converted to centres here. (The original builder kept
#                 the first n edges, putting every value at its cell's SW corner: all terrain was
#                 drawn 7.5″ ≈ 230 m S and W of its true position.) SRTM15+ is 15″ ≈ 460 m, halves
#                 real mountain slopes and is itself offset 1–2″ from Copernicus; use it only if
#                 sea-floor bathymetry is needed.

using ArchGDAL
using Downloads
using HDF5

const COPERNICUS_URL = "https://copernicus-dem-30m.s3.amazonaws.com"

"""
Bilinear interpolation on a regular, ascending lon/lat grid of cell-centre values
`z[i_lon, j_lat]`. Callable as `itp(lon_deg, lat_deg)`; points outside the grid are clamped
to its edge cells.
"""
struct GridInterp
    lon0::Float64; dlon::Float64
    lat0::Float64; dlat::Float64
    z::Matrix{Float64}
end
function (g::GridInterp)(lon::Real, lat::Real)
    nx, ny = size(g.z)
    fi = (lon - g.lon0) / g.dlon + 1; fj = (lat - g.lat0) / g.dlat + 1
    i = clamp(floor(Int, fi), 1, nx - 1); j = clamp(floor(Int, fj), 1, ny - 1)
    u = fi - i; v = fj - j
    (1-u)*(1-v)*g.z[i, j] + u*(1-v)*g.z[i+1, j] + (1-u)*v*g.z[i, j+1] + u*v*g.z[i+1, j+1]
end
covers(g::GridInterp, lon, lat) =
    g.lon0 <= lon <= g.lon0 + (size(g.z, 1) - 1) * g.dlon && g.lat0 <= lat <= g.lat0 + (size(g.z, 2) - 1) * g.dlat

# ---------------------------------------------------------------- Copernicus GLO-30 tiles
"Name of the 1° Copernicus GLO-30 tile whose south-west corner is (lat_floor, lon_floor)."
function copernicus_tile_name(lat_floor::Int, lon_floor::Int)
    ns = lat_floor < 0 ? "S" : "N"; ew = lon_floor < 0 ? "W" : "E"
    "Copernicus_DSM_COG_10_$(ns)$(lpad(abs(lat_floor), 2, '0'))_00_$(ew)$(lpad(abs(lon_floor), 3, '0'))_00_DEM"
end

"Tiles needed for points (lon, lat), padded so bilinear neighbours at tile edges are present."
function copernicus_tiles(lons, lats; pad=2 / 3600)
    tiles = Set{Tuple{Int,Int}}()
    for (lo, la) in zip(lons, lats), dlo in (-pad, pad), dla in (-pad, pad)
        push!(tiles, (floor(Int, la + dla), floor(Int, lo + dlo)))
    end
    sort!(collect(tiles))
end

"""
Paths of the requested tiles, looking first in `dir` and downloading missing ones there. Tiles
that do not exist on the server (all-ocean squares) are skipped and returned in `missing_tiles`.
"""
function fetch_copernicus_tiles(tiles, dir)
    paths = String[]; missing_tiles = Tuple{Int,Int}[]
    for (la, lo) in tiles
        name = copernicus_tile_name(la, lo)
        path = joinpath(dir, name * ".tif")
        if !isfile(path)
            resp = Downloads.request("$COPERNICUS_URL/$name/$name.tif"; output=path, throw=false)
            if !(resp isa Downloads.Response) || resp.status != 200
                isfile(path) && rm(path)
                push!(missing_tiles, (la, lo)); continue
            end
            println("  downloaded $name.tif")
        end
        push!(paths, path)
    end
    paths, missing_tiles
end

"""
Mosaic geographic GeoTIFF tiles that share one pixel lattice onto the box [lo0, lo1] × [la0, la1]
(cell centres, ascending). Cells no tile covers are set to `fill_value` (0 m: sea level, which is what
Copernicus uses over the ocean).
"""
function mosaic_tiles(files, lo0, lo1, la0, la1; fill_value=0.0)
    gts = [ArchGDAL.read(ArchGDAL.getgeotransform, f) for f in files]
    d = gts[1][2]
    all(g -> isapprox(g[2], d) && isapprox(-g[6], d), gts) ||
        error("tiles have different pixel sizes (Copernicus tiles above 50° latitude are not supported)")
    c_lon(g, i) = g[1] + (i - 0.5) * g[2]          # centre of column i
    c_lat(g, j) = g[4] + (j - 0.5) * g[6]          # centre of row j (north-up)
    lon_start = c_lon(gts[1], 0) + d * floor((lo0 - c_lon(gts[1], 0)) / d)
    lat_start = c_lat(gts[1], 0) + d * floor((la0 - c_lat(gts[1], 0)) / d)
    nlon = ceil(Int, (lo1 - lon_start) / d) + 1; nlat = ceil(Int, (la1 - lat_start) / d) + 1
    z = fill(NaN, nlon, nlat)
    for (f, g) in zip(files, gts)
        T = ArchGDAL.read(ds -> ArchGDAL.read(ArchGDAL.getband(ds, 1)), f)   # T[col, row]
        for j in axes(T, 2), i in axes(T, 1)
            io = round(Int, (c_lon(g, i) - lon_start) / d) + 1
            jo = round(Int, (c_lat(g, j) - lat_start) / d) + 1
            (1 <= io <= nlon && 1 <= jo <= nlat) && (z[io, jo] = T[i, j])
        end
    end
    nmiss = count(isnan, z)
    nmiss > 0 && println("  $(nmiss) of $(length(z)) DEM cells not covered by any tile; set to $(fill_value) m")
    replace!(z, NaN => fill_value)
    GridInterp(lon_start, d, lat_start, d, z)
end

"""
    copernicus_interp(lons, lats; tile_dir=nothing, margin=0.01)

GLO-30 interpolator covering the points (lon, lat) plus `margin` degrees. Tiles are read from /
cached in `tile_dir`; without one they go to a temporary directory that is deleted afterwards.
"""
function copernicus_interp(lons, lats; tile_dir=nothing, margin=0.01)
    lo0, lo1 = extrema(lons); la0, la1 = extrema(lats)
    tiles = copernicus_tiles(lons, lats)
    dir = tile_dir === nothing ? mktempdir() : (mkpath(tile_dir); tile_dir)
    try
        println("  Copernicus GLO-30: $(length(tiles)) tile(s) in $(dir)")
        paths, missing_tiles = fetch_copernicus_tiles(tiles, dir)
        isempty(missing_tiles) || println("  no tile on the server for $(missing_tiles) (ocean); those cells are 0 m")
        isempty(paths) && error("no Copernicus tiles available for this region")
        return mosaic_tiles(paths, lo0 - margin, lo1 + margin, la0 - margin, la1 + margin)
    finally
        tile_dir === nothing && rm(dir; recursive=true, force=true)
    end
end

# ---------------------------------------------------------------- HDF5 grids (e.g. GMT earth_relief)
"Cell-centre coordinates for an axis with `n` cells, given n+1 edges (pixel registration) or n centres."
function cell_centres(coords::Vector{Float64}, n::Int)
    length(coords) == n + 1 && return (coords[1:end-1] .+ coords[2:end]) ./ 2
    length(coords) == n     && return coords
    error("DEM axis has $(length(coords)) coordinates for $n cells")
end

"Interpolator from an HDF5 grid (`longitude`, `latitude`, `elevation[n_lat, n_lon]`), cropped to the box."
function h5_interp(path, lo0, lo1, la0, la1)
    lons, lats, elev = h5open(path) do f
        Float64.(read(f["longitude"])), Float64.(read(f["latitude"])), read(f["elevation"])
    end
    lons = cell_centres(lons, size(elev, 2))
    lats = cell_centres(lats, size(elev, 1))
    if lats[end] < lats[1]                        # north-up storage → ascending latitude
        lats = reverse(lats); elev = elev[end:-1:1, :]
    end
    li = findall(x -> lo0 <= x <= lo1, lons); ai = findall(y -> la0 <= y <= la1, lats)
    li = max(1, first(li) - 1):min(length(lons), last(li) + 1)     # one extra cell for bilinear
    ai = max(1, first(ai) - 1):min(length(lats), last(ai) + 1)
    GridInterp(lons[li[1]], lons[2] - lons[1], lats[ai[1]], lats[2] - lats[1],
               Float64.(permutedims(elev[ai, li])))
end

"""
    dem_interp(spec, lons, lats; tile_dir=nothing)

`spec == "copernicus"` → `copernicus_interp`; otherwise `spec` is an HDF5 grid path. The grid
covers the points (lon, lat); every point is checked to lie inside it.
"""
function dem_interp(spec::AbstractString, lons, lats; tile_dir=nothing)
    g = spec == "copernicus" ? copernicus_interp(lons, lats; tile_dir=tile_dir) :
        h5_interp(spec, minimum(lons) - 0.01, maximum(lons) + 0.01, minimum(lats) - 0.01, maximum(lats) + 0.01)
    nout = count(k -> !covers(g, lons[k], lats[k]), eachindex(lons))
    nout == 0 || error("$nout points lie outside the DEM grid from $spec")
    g
end
