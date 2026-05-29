"""
    upwards_ray_at(position::Coordinate{T}) -> Ray{T}
    upwards_ray_at(particle::Particle) -> Ray

Construct a `Ray` originating at `position` and pointing radially outward
from the Earth's center — the local "up" direction at that location.

The direction is computed by normalizing the position vector in
`ecefcoordinates` and converting the resulting unit vector back to
`position`'s coordinate system. Useful as a probe ray for queries like
[`is_above_topography`](@ref).

# Arguments
- `position::Coordinate{T}`: the ray origin.
- `particle::Particle`: convenience overload — uses `particle.position`.

# Returns
- A `Ray{T}` originating at `position` and pointing radially outward.
"""
function upwards_ray_at(position::Coordinate{T}) where {T<:Real}
    d = Direction(
        normalize(convert(ecefcoordinates, position).point),
        ecefcoordinates
    )
    d = convert(position.coordinate_system, d)
    return Ray(position, d)
end
upwards_ray_at(particle::Particle) = upwards_ray_at(particle.position)

"""
    is_above_topography(position::Coordinate, bvh::BVHTree) -> Bool
    is_above_topography(particle::Particle, bvh::BVHTree) -> Bool

Test whether `position` sits above all triangles in `bvh`. Returns `true`
if a ray shot radially outward from `position` (see [`upwards_ray_at`](@ref))
misses every triangle in the tree.

Used to distinguish particles in air (above topography) from particles
inside rock (below) — e.g. when filtering tau decays by their decay
medium, or when checking whether a propagated lepton ranged out inside
the mountain.

# Arguments
- `position::Coordinate`: the location to query.
- `particle::Particle`: convenience overload — uses `particle.position`.
- `bvh::BVHTree`: BVH over topography triangles (typically `g_frame["bvh"]`).

# Returns
- `true` if the upwards ray from `position` does not intersect `bvh`.
"""
function is_above_topography(position::Coordinate, bvh::BVHTree)
    return isempty(intersect_all(bvh, upwards_ray_at(position)))
end
is_above_topography(particle::Particle, bvh::BVHTree) =
    is_above_topography(particle.position, bvh)

"""
    place_detector_units(
        g_frame::Frame,
        d_frame::Frame;
        spacing            = 125.0u"m",
        max_slope_deg      = 35.0,
        half_lengths       = [1.0u"m", 1.0u"m", 0.125u"m"],
        grid_margin        = 500.0u"m",
        tilt_mode          = :terrain,
        fixed_tilt_deg     = nothing,
    ) -> (Vector{OBB{Float64}}, Union{BVHTree, Nothing})

Lay out detector OBBs on a hexagonal grid covering the detector surface
encoded by `d_frame["detector_bvh"]`, returning both the OBBs and a BVH
over them. Pure function — does not mutate either frame.

The grid is laid out in the local-tangent plane derived from the
area-weighted mean of the detector-region triangle normals, with
per-axis tilt correction so the *projected* nearest-neighbor distance
on the surface matches `spacing`. Grid points whose surface-slope
exceeds `max_slope_deg` get dropped; the rest receive OBBs whose
orientation is set by `tilt_mode` (each module's local triangle normal,
or one fixed array-wide tilt). The array is otherwise uniform (single
`spacing`); use `half_lengths` to set the module footprint.

Typical caller pattern:

    obbs, obb_bvh = place_detector_units(g_frame, d_frame; spacing=125.0u"m")
    d_frame["detector_units"]    = obbs
    d_frame["detector_unit_bvh"] = obb_bvh

# Arguments
- `g_frame::Frame`: provides the local coordinate system via `g_frame["cs"]`.
- `d_frame::Frame`: provides the detector-region BVH via `d_frame["detector_bvh"]`.

# Keyword arguments
- `spacing`: target nearest-neighbor distance between modules along the surface.
- `max_slope_deg`: surface-slope cutoff in degrees; triangles steeper than
  this get no module placed on them.
- `half_lengths`: half-extents of each OBB along its local (x, y, z) axes.
- `grid_margin`: extra distance past the detector-centroid bounding box used
  when sizing the candidate grid (handles edge effects from irregular
  detector outlines, FP noise, hex offsets pushing rows just outside).
- `tilt_mode`: orientation strategy for every placed module. `:terrain`
  (default) aligns each OBB to its own local triangle normal; `:fixed`
  gives every OBB one shared orientation. The slope filter always uses each
  site's local normal, so `tilt_mode` changes only the assigned orientation,
  not which sites survive.
- `fixed_tilt_deg`: only valid with `tilt_mode=:fixed`. `nothing` (default)
  freezes every module at the area-weighted mean detector normal. A number
  sets the panel tilt angle from horizontal — `0` = horizontal (normal up),
  `90` = vertical — in the azimuth of the mean normal's horizontal projection
  (tilts "downhill"; azimuth defaults to +x if the mean normal is vertical).
  Must lie in `[0, 180]`.

# Returns
- `(obbs, obb_bvh)` — `Vector{OBB{Float64}}` of placed modules and a
  `BVHTree` over them suitable for fast hit queries. If no module
  survives placement (e.g. spacing too coarse, slope filter too strict,
  or empty detector region), `obbs` is empty and `obb_bvh` is `nothing`;
  callers should check for this case before storing the result.
"""
function place_detector_units(
    g_frame::Frame,
    d_frame::Frame;
    spacing       = 125.0u"m",
    max_slope_deg = 35.0,
    half_lengths  = [1.0u"m", 1.0u"m", 0.125u"m"],
    grid_margin   = 500.0u"m",
    tilt_mode      = :terrain,
    fixed_tilt_deg = nothing,
)
    tilt_mode in (:terrain, :fixed) ||
        throw(ArgumentError("tilt_mode must be :terrain or :fixed, got $(repr(tilt_mode))"))
    fixed_tilt_deg === nothing || tilt_mode === :fixed ||
        throw(ArgumentError("fixed_tilt_deg is only valid with tilt_mode=:fixed"))
    fixed_tilt_deg === nothing || (0 ≤ fixed_tilt_deg ≤ 180) ||
        throw(ArgumentError("fixed_tilt_deg must be in [0, 180] degrees, got $fixed_tilt_deg"))

    cs  = g_frame["cs"]
    bvh = d_frame["detector_bvh"]
    det_triangles = bvh.triangles

    # Area-weighted mean detector-surface normal. The (a/total_a) ratio is
    # dimensionally clean (m²/m² → NoDims), but the resulting SVector has
    # `Quantity{NoDims}` components — Direction requires bare Reals, so
    # we ustrip just before constructing it.
    areas     = area.(det_triangles)
    centroids = [(t.v1.point + t.v2.point + t.v3.point) ./ 3 for t in det_triangles]
    normals   = [normal(t).point for t in det_triangles]
    total_a   = sum(areas)
    wn_dim    = sum((a / total_a) .* n for (a, n) in zip(areas, normals))

    direction = Direction(ustrip.(wn_dim), cs)
    up        = Direction([0.0, 0.0, 1.0], cs)

    # Per-site 2D tilt correction: each spacing is reduced by cos(slope) in
    # its respective direction so the projected horizontal step matches the
    # target surface spacing.
    nx, ny, nz = direction.point
    Δx        = (nz / sqrt(nx^2 + nz^2)) * spacing
    Δy_grid   = (nz / sqrt(ny^2 + nz^2)) * spacing * sqrt(3) / 2

    # Grid bounds from the detector centroid extents + margin.
    xs_raw = [c[1] for c in centroids]
    ys_raw = [c[2] for c in centroids]
    x_lo = minimum(xs_raw) - grid_margin
    x_hi = maximum(xs_raw) + grid_margin
    y_lo = minimum(ys_raw) - grid_margin
    y_hi = maximum(ys_raw) + grid_margin

    base_xs = collect(x_lo:Δx:x_hi)
    base_ys = collect(y_lo:Δy_grid:y_hi)

    # Candidate grid points whose vertical ray hits a detector triangle.
    ps = Coordinate[]
    for (idx, y) in enumerate(base_ys)
        xoffset = mod(idx, 2) == 0 ? 0.0u"m" : Δx / 2
        xs = base_xs .+ xoffset
        coords = [Coordinate(x, y, 0.0u"m", cs) for x in xs]
        rays   = Ray.(coords, Ref(up))
        for ray in rays
            isempty(intersect_all(bvh, ray)) && continue
            push!(ps, ray.origin)
        end
    end

    # OBBs aligned to the local triangle normal, slope-filtered.
    max_slope_rad = deg2rad(max_slope_deg)

    # In :fixed tilt mode every module shares one orientation, computed once
    # here. With no `fixed_tilt_deg` the shared orientation is the area-weighted
    # mean detector normal (`direction`). With an explicit `fixed_tilt_deg` the
    # panel normal is set to that polar angle from vertical (0° = horizontal
    # panel, 90° = vertical), in the azimuth of the mean normal's horizontal
    # projection (so it tilts "downhill"); azimuth defaults to +x when the mean
    # normal is vertical.
    fixed_normal = if tilt_mode === :fixed && fixed_tilt_deg !== nothing
        θ = deg2rad(fixed_tilt_deg)
        nx, ny, _ = direction.point
        φ = hypot(nx, ny) < eps(Float64) ? 0.0 : atan(ny, nx)
        Direction([sin(θ) * cos(φ), sin(θ) * sin(φ), cos(θ)], cs)
    else
        direction
    end
    # (Same NaN-safe AngleAxis construction as the per-site case below.)
    fixed_rot = let ψf = acos(clamp(dot(fixed_normal, up), -1.0, 1.0))
        ψf < eps(Float64) ? AngleAxis(0.0, 1.0, 0.0, 0.0) :
                            AngleAxis(ψf, cross(up, fixed_normal)...)
    end

    obbs = OBB{Float64}[]
    for p in ps
        ray = Ray(p, up)
        ixs = intersect_all(bvh, ray)
        isempty(ixs) && continue
        ψ = acos(clamp(dot(ixs[1].normal, up), -1.0, 1.0))
        ψ > max_slope_rad && continue
        # When ψ ≈ 0 the cross-product axis collapses to (0,0,0); AngleAxis
        # normalization then yields NaN and poisons the OBB. The rotation
        # is the identity in that limit, so dispatch to a safe axis.
        local_rot = if ψ < eps(Float64)
            AngleAxis(0.0, 1.0, 0.0, 0.0)
        else
            AngleAxis(ψ, cross(up, ixs[1].normal)...)
        end
        rot = tilt_mode === :fixed ? fixed_rot : local_rot
        center = ixs[1].point
        push!(obbs, OBB(center, rot, half_lengths))
    end

    return obbs, isempty(obbs) ? nothing : BVHTree(obbs)
end

"""
    rock_traversed(ray::Ray{T}, bvh::BVHTree; cap = Inf*u"m") -> (path_length, grammage)

Rock path length and column depth a `ray` crosses through the topography
mesh `bvh`, out to a distance `cap` along the ray.

Segments are classified air vs rock by [`compute_density`](@ref): a segment
denser than `AIR_DENSITY` counts as rock, and only rock segments contribute
to the returned totals. The final segment is clipped at `cap`.

# Returns
- `(path_length, grammage)` — rock path length (`u"km"`) and column depth
  (`u"g/cm^2"`).
"""
function rock_traversed(ray::Ray{T}, bvh::BVHTree;
                        cap::Quantity = Inf * u"m") where {T}
    ixs = Vector{Intersection{T}}(intersect_all(bvh, ray))
    isempty(ixs) && return (0.0u"km", 0.0u"g/cm^2")
    dens = compute_density(ixs, ray.direction)
    lens = compute_lengths(ixs)
    pathlen, grammage, remaining = 0.0u"m", 0.0u"g/cm^2", cap
    for (l, ρ) in zip(lens, dens)
        remaining <= 0.0u"m" && break
        seg = min(l, remaining)                # clip the final partial segment
        if ρ > AIR_DENSITY                     # rock segment
            pathlen  += seg
            grammage += ρ * seg
        end
        remaining -= seg
    end
    return (pathlen |> u"km", grammage |> u"g/cm^2")
end

"""
    rock_overburden(qframe::Frame; initial_key = "injection_initial_state")
        -> (path_length, grammage)

Rock an event's primary traverses between its injection point and where its
forward trajectory first enters the detector region — the "overburden" that
governs whether a muon survives to the detector.

The initial-state `Particle` is read from `qframe[initial_key]`; its forward
ray is capped at the detector-region entry (`qframe["detector_bvh"]`) and run
through the topography BVH (`qframe["bvh"]`) by [`rock_traversed`](@ref). Both
BVHs are resolved via frame-parent inheritance, so `qframe` must have its G
and D parents attached.

Throws if the trajectory never enters the detector region.

# Returns
- `(path_length, grammage)` — see [`rock_traversed`](@ref).
"""
function rock_overburden(qframe::Frame;
                         initial_key::String = "injection_initial_state")
    p     = qframe[initial_key]::Particle
    ray   = Ray(p)
    entry = find_intersect(ray, qframe["detector_bvh"])
    entry === nothing && error(
        "rock_overburden: trajectory from `$initial_key` never enters the " *
        "detector region")
    return rock_traversed(ray, qframe["bvh"]; cap = entry.distance)
end
