# 6_detector_layout.jl
#
# Walk through the OBB placement algorithm that templates/2_create_detector.jl
# wraps as a CLI. Designed to be pasted into the REPL section by section —
# values display themselves rather than being wrapped in println.
#
# We run the algorithm live on the canonical Colca-valley geometry, which
# ships without detector units placed. Each section corresponds to one
# block of `build_detector_units` (see templates/2_create_detector.jl).
#
# For frame-container basics, see 1_frame_usage.jl.
#
# Topics covered:
#   1. Inputs — what `build_gcd_bundle` already put in the D frame
#   2. Area-weighted centroid + normal of the detector surface
#   3. Hex-grid spacing in the local tangent plane (with tilt correction)
#   4. Vertical-ray projection: which grid points actually hit the surface
#   5. Per-point OBB construction with the max-slope filter
#   6. The resulting D-frame keys, and how 6_corsika_hits.jl consumes them

using LinearAlgebra
using Rotations
using Tambo
using Unitful: ustrip, @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")

# =============================================================================
# 1. Inputs — what's already in the D frame
# =============================================================================
# build_gcd_bundle (the function 1_create_geometry.jl ends with) populates
# the D frame with two keys: detector_region (1-based face indices into
# the topography mesh that mark the detector area) and detector_bvh (a
# BVH built over those triangles, for fast ray queries). What it does
# NOT add is detector_units / detector_unit_bvh — those are the OBBs
# this walkthrough builds.

frames = load_frames(geometry_file)
gframe = frames.g_frames[end]
dframe = frames.d_frames[end]

sort(collect(keys(dframe.data)))    # ["detector_bvh", "detector_region"]
haskey(dframe, "detector_units")    # false — confirms we have something to build

cs  = gframe["cs"]                   # local Cartesian coord system
bvh = dframe["detector_bvh"]
det_triangles = bvh.triangles
@show length(det_triangles);         # number of detector-region triangles

# Module dimensions — half-lengths in (x, y, z) of the local OBB frame.
# Default ~2 m × 2 m × 0.25 m panels, matched to current Tambo prototypes.
const HALF_LENGTHS = [1.0u"m", 1.0u"m", 0.125u"m"]

# =============================================================================
# 2. Area-weighted centroid + normal of the detector surface
# =============================================================================
# The detector region is generally tilted and curved. The placement
# algorithm flattens it into a single tangent plane by taking the
# area-weighted mean of triangle centroids (gives a plane "anchor") and
# the area-weighted mean of normals (gives the plane orientation).
# Larger triangles count more; spurious tiny triangles can't drag the
# anchor or normal much.

areas     = Tambo.area.(det_triangles)                                       # Quantity{m²}
centroids = [(t.v1.point + t.v2.point + t.v3.point) ./ 3                     # Quantity{m}, 3-vectors
             for t in det_triangles]
normals   = [Tambo.normal(t).point for t in det_triangles]                   # unit-vectors (unitless)

total_area = sum(areas)
@show total_area;                    # total detector-region surface area (m²)

# Area-weighted means. The centroid sum carries units of m³ (m² · m), and
# dividing by total_area returns m. The normal weights collapse to
# dimensionless via a/total_area, so the mean normal stays unitless.
wc = sum(a .* c for (a, c) in zip(areas, centroids)) ./ total_area
wn = sum((a / total_area) .* n for (a, n) in zip(areas, normals))

point     = Tambo.Coordinate(wc, cs)
direction = Tambo.Direction(wn, cs)
plane     = Tambo.Plane(point, direction)
up        = Tambo.Direction([0.0, 0.0, 1.0], cs)

@show plane.point.point;             # anchor of the local tangent plane
@show plane.normal.point;            # mean unit normal in CS coords (nx, ny, nz)

# =============================================================================
# 3. Hex-grid spacing in the local tangent plane
# =============================================================================
# We want a uniform-density module layout on the *projected* horizontal
# footprint of the detector. The grid is laid out in (x, y) at z = 0 and
# then projected vertically onto the surface in Section 4.
#
# Two corrections are needed for tilted surfaces. If the mean normal is
# n = (nx, ny, nz), the tangent plane tilts in x by angle atan(nx, nz)
# and in y by atan(ny, nz). Walking a fixed surface distance `spacing`
# projects to a horizontal step of cos(slope) · spacing in each direction.
# That's what the Δx / Δy_grid factors below capture.

spacing       = 125.0u"m"            # nearest-neighbor distance between modules
max_slope_deg = 35.0                 # threshold for skipping near-vertical patches
max_slope_rad = deg2rad(max_slope_deg)

n_vec = plane.normal.point
nx, ny, nz = n_vec[1], n_vec[2], n_vec[3]
Δx       = (nz / sqrt(nx^2 + nz^2)) * spacing
Δy_grid  = (nz / sqrt(ny^2 + nz^2)) * spacing * sqrt(3) / 2

@show Δx;                            # horizontal x-spacing (≤ spacing)
@show Δy_grid;                       # horizontal y-spacing (hex rows; ≤ spacing·√3/2)

# Constant for the row-offset margin used to widen the bounding box so
# edge effects (irregular detector outline, FP noise, hex offsets pushing
# rows just outside the bounds) don't truncate placements:
const GRID_MARGIN = 500.0u"m"

xs_raw = [c[1] for c in centroids]
ys_raw = [c[2] for c in centroids]
x_lo = minimum(xs_raw) - GRID_MARGIN
x_hi = maximum(xs_raw) + GRID_MARGIN
y_lo = minimum(ys_raw) - GRID_MARGIN
y_hi = maximum(ys_raw) + GRID_MARGIN

base_xs = collect(x_lo:Δx:x_hi)
base_ys = collect(y_lo:Δy_grid:y_hi)

@show length(base_xs) length(base_ys);   # hex grid will have at most this many rows × cols

# =============================================================================
# 4. Vertical-ray projection: which grid points hit the surface
# =============================================================================
# For each grid point (x, y, 0) we shoot a vertical ray (direction = up)
# and ask whether it intersects any detector triangle. The grid-point
# anchors are at z = 0 in the local CS (i.e. centred on the local PREM
# sphere); the actual terrain crossing happens later. Hex offsetting:
# every other row is shifted by Δx/2 in x, which produces the
# triangular-lattice neighbour structure (six neighbours at distance
# ≈ spacing).

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

@show length(ps);                    # candidate grid points that project onto the detector

# =============================================================================
# 5. Per-point OBB construction + slope filter
# =============================================================================
# For each surviving grid point, we re-shoot the vertical ray to find the
# actual surface intersection point and its triangle normal. The OBB is
# then aligned to that local normal so its short axis follows the
# terrain — modules sit flush with the slope rather than horizontally.
#
# The slope filter drops points whose triangle normal makes an angle
# greater than max_slope_rad with vertical. Steep cliffs and overhangs
# are usually unsuitable for module placement anyway.

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

@show length(obbs);                  # final placed-module count

obbs[1]                              # one OBB — center, rotation, half-lengths

# How many candidates got dropped by the slope filter?
@show length(ps) - length(obbs);

# =============================================================================
# 6. Storing the result on the D frame
# =============================================================================
# templates/2_create_detector.jl finishes by writing the OBB list and a
# BVH over them back to the D frame, then re-saving the GCD bundle.
# `detector_unit_bvh` is what 6_corsika_hits.jl looks for — without it,
# that script errors with a pointer back to this placement step.

obb_bvh = Tambo.BVHTree(obbs)

dframe["detector_units"]    = obbs
dframe["detector_unit_bvh"] = obb_bvh

sort(collect(keys(dframe.data)))    # now includes detector_units + detector_unit_bvh

# To make this layout persist beyond the REPL, save the frames:
#
#     save_frames("custom_site_with_units.jld2", frames, streams=('G','C','D'))
#
# Or just run templates/2_create_detector.jl, which is the same
# algorithm wrapped as a CLI. Both paths ultimately call the library
# helper `Tambo.place_detector_units(gframe, dframe; spacing, max_slope_deg)`,
# which collapses Sections 2–5 into one call and returns the same
# `(obbs, obb_bvh)` you'd get above.
