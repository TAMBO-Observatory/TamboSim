"""
add_detector_units.jl

Load each candidate site GCD bundle, compute the OBBs (detection units)
from the detector surface, and store them back in the D frame.

The OBBs are placed on a hexagonal grid that is projected onto the detector
surface triangles. The grid extent is derived from the actual detector
centroids for each site rather than being hardcoded.

Keys added to the D frame:
  "detector_units"     — Vector{OBB{Float64}}, one per module
  "detector_unit_bvh"  — BVHTree over those OBBs (for fast hit queries)

Output: each candidate_site_N.jld2 is overwritten in-place with the
updated D frame.
"""

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using LinearAlgebra
using Rotations
using Tambo
using Unitful

const GEO_DIR      = joinpath(tambo_path, "resources", "geometry")
const Δy           = 125.0u"m"
const HALF_LENGTHS = [1.0u"m", 1.0u"m", 0.125u"m"]
const GRID_MARGIN  = 500.0u"m"
const MAX_SLOPE    = parse(Float64, get(ENV, "MAX_SLOPE_DEG", "35"))  # degrees

function build_detector_units(gframe::Frame, dframe::Frame; max_slope_deg=MAX_SLOPE)
    cs  = gframe["cs"]
    bvh = dframe["detector_bvh"]
    det_triangles = bvh.triangles

    # Area-weighted centroid and normal of the detector surface
    areas     = ustrip.(u"m^2", Tambo.area.(det_triangles))
    centroids = [ustrip.(u"m", (t.v1.point + t.v2.point + t.v3.point) ./ 3)
                 for t in det_triangles]
    normals   = [Tambo.normal(t).point for t in det_triangles]
    total_a   = sum(areas)
    wc = sum(a .* c for (a, c) in zip(areas, centroids)) ./ total_a
    wn = sum(a .* n for (a, n) in zip(areas, normals))
    point     = Tambo.Coordinate(wc .* u"m", cs)
    direction = Tambo.Direction(wn, cs)
    plane     = Tambo.Plane(point, direction)
    up        = Tambo.Direction([0.0, 0.0, 1.0], cs)

    # Per-site 2D tilt correction: project the hex grid spacings onto the
    # horizontal plane using the mean detector surface normal n = (nx, ny, nz).
    # Each spacing is reduced by cos(slope) in its respective direction.
    n_vec = plane.normal.point  # unit normal in CS [nx, ny, nz]
    nx, ny, nz = n_vec[1], n_vec[2], n_vec[3]
    # Δy is the target nearest-neighbor distance on the surface.
    # In a hex grid: within-row spacing = d, row spacing = d*sqrt(3)/2.
    # The tilt correction maps each 3D surface distance to its horizontal projection:
    # horizontal = d * nz / sqrt(n_perp^2 + nz^2), where n_perp is the normal component
    # in that direction.
    Δx        = (nz / sqrt(nx^2 + nz^2)) * Δy
    Δy_grid   = (nz / sqrt(ny^2 + nz^2)) * Δy * sqrt(3) / 2

    # Grid bounds from detector centroid extents + margin
    xs_raw = [c[1] for c in centroids] .* u"m"
    ys_raw = [c[2] for c in centroids] .* u"m"
    x_lo = minimum(xs_raw) - GRID_MARGIN
    x_hi = maximum(xs_raw) + GRID_MARGIN
    y_lo = minimum(ys_raw) - GRID_MARGIN
    y_hi = maximum(ys_raw) + GRID_MARGIN

    base_xs = collect(x_lo:Δx:x_hi)
    base_ys = collect(y_lo:Δy_grid:y_hi)

    # Find grid points that project onto the detector surface
    ps = Tambo.Coordinate[]
    for (idx, y) in enumerate(base_ys)
        xoffset = mod(idx, 2) == 0 ? 0.0u"m" : Δx / 2
        xs = base_xs .+ xoffset
        coords = [Tambo.Coordinate(x, y, 0.0u"m", cs) for x in xs]
        rays   = Tambo.Ray.(coords, Ref(up))
        for ray in rays
            isempty(Tambo.intersect_all(bvh, ray)) && continue
            push!(ps, ray.origin)
        end
    end

    # Build OBBs aligned to the local terrain normal at each grid point
    max_slope_rad = deg2rad(max_slope_deg)
    obbs = Tambo.OBB{Float64}[]
    for p in ps
        ray = Tambo.Ray(p, up)
        ixs = Tambo.intersect_all(bvh, ray)
        isempty(ixs) && continue
        n̂ = cross(up, ixs[1].normal)
        ψ = acos(clamp(dot(ixs[1].normal, up), -1.0, 1.0))
        ψ > max_slope_rad && continue
        rot    = AngleAxis(ψ, n̂...)
        center = ixs[1].point
        push!(obbs, Tambo.OBB(center, rot, HALF_LENGTHS))
    end

    return obbs, Tambo.BVHTree(obbs)
end

site_files = sort(filter(f -> startswith(basename(f), "candidate_site_"), readdir(GEO_DIR, join=true)))

println("Adding detector units to $(length(site_files)) candidate site GCD bundles (max slope: $(MAX_SLOPE)°)\n")

for jld2_path in site_files
    site = replace(basename(jld2_path), ".jld2" => "")
    frames = load_frames(jld2_path)
    gframe = Tambo._get_last_frame(frames, 'G')
    dframe = Tambo._get_last_frame(frames, 'D')

    obbs, obb_bvh = build_detector_units(gframe, dframe)

    dframe["detector_units"]    = obbs
    dframe["detector_unit_bvh"] = obb_bvh

    save_frames(jld2_path, frames, streams=('G', 'C', 'D'))

    sz_mb = round(filesize(jld2_path) / 1024^2, digits=1)
    println("  $site: $(length(obbs)) modules → $(sz_mb) MB")
end

println("\nDone.")
