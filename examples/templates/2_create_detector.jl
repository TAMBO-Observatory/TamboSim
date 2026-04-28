# 2_create_detector.jl
#
# Place detector units (OBBs) on a single GC bundle and write them back into
# the D frame. The modules are laid out on a hexagonal grid projected onto
# the detector surface triangles, with a max-slope filter that skips
# near-vertical patches.
#
# Input: a GC bundle JLD2 produced by 1_create_geometry.jl.
# Output: the same JLD2 (or a path passed via --output), with two new keys
# on the D frame:
#
#   "detector_units"     — Vector{OBB{Float64}}, one per module
#   "detector_unit_bvh"  — BVHTree over those OBBs (for fast hit queries)
#
# Default behavior overwrites the input file in place.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using ArgParse
using LinearAlgebra
using Rotations
using Tambo
using Unitful

const HALF_LENGTHS = [1.0u"m", 1.0u"m", 0.125u"m"]
const GRID_MARGIN  = 500.0u"m"

# NOTE: this function is also defined verbatim in
# _internal/add_detector_units_batch.jl. Both copies will be removed once the
# algorithm is lifted into Tambo proper as `Tambo.place_detector_units`.
function build_detector_units(gframe::Frame, dframe::Frame, spacing; max_slope_deg)
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
    Δx        = (nz / sqrt(nx^2 + nz^2)) * spacing
    Δy_grid   = (nz / sqrt(ny^2 + nz^2)) * spacing * sqrt(3) / 2

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

# =============================================================================
# Main
# =============================================================================

function parse_commandline()
    s = ArgParseSettings(
        description = "Place detector units on a single GC bundle and save"
    )

    @add_arg_table! s begin
        "--input", "-i"
            help = "Path to GC bundle JLD2 (produced by 1_create_geometry.jl)"
            arg_type = String
            required = true
        "--output", "-o"
            help = "Output JLD2 path (defaults to overwriting --input)"
            arg_type = String
            default = ""
        "--spacing"
            help = "Target nearest-neighbor distance between modules in m"
            arg_type = Float64
            default = 125.0
        "--slope"
            help = "Max surface slope in degrees; steeper patches get no module"
            arg_type = Float64
            default = 35.0
    end

    return parse_args(s)
end

args = parse_commandline()

infile  = args["input"]
outfile = isempty(args["output"]) ? infile : args["output"]
spacing = args["spacing"] * u"m"
slope   = args["slope"]

frames = load_frames(infile)
gframe = frames.g_frames[end]
dframe = frames.d_frames[end]

obbs, obb_bvh = build_detector_units(gframe, dframe, spacing; max_slope_deg=slope)

dframe["detector_units"]    = obbs
dframe["detector_unit_bvh"] = obb_bvh

save_frames(outfile, frames, streams=('G', 'C', 'D'))

sz_mb = round(filesize(outfile) / 1024^2, digits=1)
println("Placed $(length(obbs)) modules (spacing $(args["spacing"]) m, max slope $(slope)°)")
println("  $infile → $outfile  ($sz_mb MB)")
