# De-thinning: per-panel Poisson resampling of thinned CORSIKA ground particles
# (Billoir 2008, Astropart. Phys. 30, 270). Used by `read_corsika_hits!` unless its
# config sets "dethin" = false. Matters for showers with EM thinning
# (≳ 2 PeV shower energy, with our standard CORSIKA settings).
#
# In CORSIKA, thinning significantly reduces the number of tracked low-energy EM
# particles: at an interaction, only one secondary is kept, and its weight is
# raised (w > 1) to stand in for the dropped ones. Projected as-is, such a
# particle hits at most one panel and carries all of w, so per-panel hit counts
# come out too low. De-thinning instead replaces it with weight-1 clones spread
# over the area its dropped siblings would have covered.
#
# Method, per shower and per panel P:
#  - Π_P is the plane through P's center perpendicular to the shower axis.
#    Each thinned particle's straight line crosses Π_P at x.
#  - The sampling region S around P is a patch of the shower plane, of side
#    s = clamp(ε r_P, s_min, s_max), where r_P is P's distance from the axis.
#    It is an annular sector when r_P > s, else a disk of diameter s.
#  - Every thinned particle whose crossing x lies in S spawns Poisson(w A_T / A_S)
#    clones. The clones are spread uniformly over a disk T ⊂ Π_P around P that
#    contains P's footprint along the particle direction.
#  - A clone keeps the parent's species, energy, direction and arrival time at Π_P.
#    It counts as a hit on P iff its line enters P's box.
# Particles with w ≈ 1 bypass all this and go through `_corsika_module_hit` as usual.
#
# Choosing the sampling-region size s. A smaller S follows the lateral density
# more closely, but each parent in it then puts more clones on the panel P
# (w A_P / A_S on average), so a panel's hits come in clusters of identical
# clones. A larger S averages over more parents. Choose s_max well below the
# panel spacing, or neighboring panels will draw on the same parents and their
# hit counts will be correlated. The defaults (ε = 0.15, s_min = 4 m,
# s_max = 30 m) give s = 4 m near the axis, 15 m at 100 m and 30 m beyond 200 m.
#
# Random numbers. Each panel draws from its own RNG, seeded by (seed, shower,
# panel index). So masking a design's hits to a subset of its panels gives the
# same hits as de-thinning that subset (see `unit_ids`), and two designs that
# share panel indices (e.g. two fixed tilts on one grid) draw the same parents
# for each panel.
# Draws are reproducible for a fixed Manifest (the Xoshiro seeding and the Poisson
# sampler may change between Julia / Distributions versions).
#
# Validation and limits. This implementation was checked when first written
# against CORSIKA showers at 6–13 PeV run both without thinning and with
# thinning at maximum weights of 50 and 500. Per-panel particle counts, panel
# multiplicities and first-arrival times matched the unthinned showers at both
# weights.
# Within-panel spreads in arrival time and energy can show too little variation,
# because a clone copies its parent's energy and time. At maximum weight 500 both
# spreads came out too small beyond ~150 m from the axis. Our standard CORSIKA
# settings cap weights at about E / 2 PeV, so this matters mainly for showers
# near 1 EeV and above. A possible fix (not implemented) is to give each clone
# the energy and time of a random parent drawn from a wider pool at the same core
# distance.

"""
    corsika_shower_axis(shower_dir, cs) -> (point, dir)

The primary's injection point and direction for one `tambo_shower` output
directory, rotated into `cs`. CORSIKA writes these in the same mesh frame as the
ground particles (ECEF axes, origin at the mesh bounding-box center), in
`primary/config.yaml` and `primary/summary.yaml`.
"""
function corsika_shower_axis(shower_dir, cs)
    for f in ("config.yaml", "summary.yaml")
        isfile(joinpath(shower_dir, "primary", f)) || error(
            "corsika_shower_axis: $shower_dir has thinned particles but no primary/$f, " *
            "which de-thinning needs for the shower axis.")
    end
    dir_rot, offset = precompute_cs_transform(ecefcoordinates, cs)
    cfg = YAML.load_file(joinpath(shower_dir, "primary", "config.yaml"))
    center = SVector{3}(Float64.(cfg["frame"]["center"])) .* u"m"
    s = YAML.load_file(joinpath(shower_dir, "primary", "summary.yaml"))["shower_0"]
    point = dir_rot * (SVector(s["x"], s["y"], s["z"]) .* u"m" .+ offset .+ center)
    dir = normalize(dir_rot * SVector{3,Float64}(s["nx"], s["ny"], s["nz"]))
    return (; point, dir)
end

# FNV-1a over the last `n` path components (`event_XXXXXX/shower_N`): a shower key
# that does not depend on where the campaign lives, unlike `hash` of the full path.
function _stable_path_key(path; n = 2)
    parts = splitpath(normpath(path))
    h = 0xcbf29ce484222325
    for b in codeunits(join(parts[max(1, end-n+1):end], "/"))
        h = (h ⊻ b) * 0x100000001b3
    end
    return h
end

"""
    resample_shower_hits(seed, events, axis, units, det_bvh, topo_bvh; kwargs...)
        -> Vector{NamedTuple}

Hit records `(particle, module_index, weight)` for one shower. Unthinned
particles go through [`_corsika_module_hit`](@ref). Thinned particles are
replaced by weight-1 clones, as described in `src/corsika/corsika_dethin.jl`.
`axis` is a `(point, dir)` NamedTuple (see [`corsika_shower_axis`](@ref)); it is
only used when the shower has thinned particles (it may also be a zero-argument
function returning it, so the `primary/` files are read only when needed). Panel
`k` draws from `Xoshiro([seed, unit_ids[k]])`.

Keyword arguments:
- `ε = 0.15`: sampling-region side as a fraction of the core distance.
- `s_min = 4.0u"m"`, `s_max = 30.0u"m"`: bounds on that side.
- `margin = 30.0u"m"`: candidate search margin, for transverse drift between
  the ground crossing and Π_P.
- `w_unthinned = 1 + 1e-6`: weights at or below this count as unthinned.
- `max_tanα = 5.0`: parents more inclined than this to the axis are dropped.
- `unit_ids = eachindex(units)`: per-panel seed keys. A caller that passes a
  subset of a design's panels can pass their indices in the full design to get
  the same draws.
"""
function resample_shower_hits(seed::Integer, events, axis, units, det_bvh, topo_bvh;
                              ε = 0.15, s_min = 4.0u"m", s_max = 30.0u"m", margin = 30.0u"m",
                              w_unthinned = 1 + 1e-6, max_tanα = 5.0,
                              unit_ids = eachindex(units))
    hits = CorsikaHitRec[]
    thinned = CorsikaEvent{Float64}[]
    for ev in events
        if ev.weight <= w_unthinned
            h = _corsika_module_hit(ev, det_bvh, topo_bvh)
            h === nothing || push!(hits, h)
        else
            push!(thinned, ev)
        end
    end
    isempty(thinned) && return hits
    axis = axis isa Function ? axis() : axis

    # The shower-plane geometry below works in bare metres.
    s_min, s_max, margin = ustrip.(u"m", (s_min, s_max, margin))
    a = axis.dir
    e1, e2 = _plane_basis(a)
    O = axis.point
    proj(x) = (v = ustrip.(u"m", x .- O); (dot(v, e1), dot(v, e2)))

    # Coarse grid over the axis-projected ground positions, for candidate lookup.
    cell = 10.0
    key(ρ) = (floor(Int, ρ[1] / cell), floor(Int, ρ[2] / cell))
    grid = Dict{Tuple{Int,Int},Vector{Int}}()
    for (i, ev) in enumerate(thinned)
        push!(get!(grid, key(proj(ev.particle.position.point)), Int[]), i)
    end

    cs = first(thinned).particle.position.coordinate_system
    for (k, obb) in enumerate(units)
        rng = Xoshiro(UInt64[seed % UInt64, unit_ids[k]])
        c = obb.center.point
        R = _Region(proj(c), clamp(ε * hypot(proj(c)...), s_min, s_max))
        hdiag = ustrip(u"m", norm(obb.half_extents))
        reach = ceil(Int, (R.s / 2 + margin) / cell)
        k0 = key(R.ρP)
        for gx in k0[1]-reach:k0[1]+reach, gy in k0[2]-reach:k0[2]+reach
            for i in get(grid, (gx, gy), Int[])
                _clone_onto!(hits, rng, thinned[i], k, c, R, a, e1, e2, proj,
                             hdiag, max_tanα, cs, det_bvh, topo_bvh)
            end
        end
    end
    return hits
end

# Orthonormal basis (e1, e2) of the plane perpendicular to `a`.
function _plane_basis(a)
    h = abs(a[3]) < 0.9 ? SVector(0.0, 0.0, 1.0) : SVector(1.0, 0.0, 0.0)
    e1 = normalize(cross(a, h))
    return e1, cross(a, e1)
end

# The sampling region S around a panel at shower-plane position ρP = (u, v), in m.
struct _Region
    ρP::NTuple{2,Float64}
    rP::Float64
    φP::Float64
    s::Float64
    sector::Bool
    area::Float64
end

function _Region(ρP, s)
    rP = hypot(ρP...)
    sector = rP > s
    area = sector ? s^2 : π * s^2 / 4
    return _Region(ρP, rP, atan(ρP[2], ρP[1]), s, sector, area)
end

function Base.in(ρ::NTuple{2,Float64}, R::_Region)
    R.sector || return hypot(ρ[1] - R.ρP[1], ρ[2] - R.ρP[2]) <= R.s / 2
    abs(hypot(ρ...) - R.rP) <= R.s / 2 || return false
    Δφ = mod(atan(ρ[2], ρ[1]) - R.φP + π, 2π) - π
    return abs(Δφ) * R.rP <= R.s / 2
end

function _clone_onto!(hits, rng, ev, k, c, R, a, e1, e2, proj, hdiag, max_tanα,
                      cs, det_bvh, topo_bvh)
    p = ev.particle
    d = p.direction.point
    da = dot(d, a)
    abs(da) < 0.05 && return               # travelling along the shower plane
    tanα = norm(d .- da .* a) / abs(da)
    tanα > max_tanα && return

    # crossing with Π_P (t in m along d) and whether it falls in S
    t = dot(ustrip.(u"m", c .- p.position.point), a) / da
    x = p.position.point .+ d .* (t * u"m")
    proj(x) in R || return

    # Same air/rock budget as `_corsika_module_hit`. If the parent crossed Π_P
    # before reaching the ground (t < 0), its traceback from the ground to Π_P must
    # pass. If it reached the ground first (t > 0), its siblings in S still land
    # around P. P then has to see upstream along d for that distance, or P is shadowed.
    max_air, max_rock = _traceback_cap(p)
    abs(t) * u"m" > max_air && return
    seg = t < 0 ? Ray(p.position, Direction(-d, cs)) :
                  Ray(Coordinate(c, cs), Direction(-d, cs))
    _, rock_gram = rock_traversed(seg, topo_bvh; cap = abs(t) * u"m")
    rock_gram > max_rock && return

    # Clones: uniform on the disk T (radius RT) around P in Π_P, with expected
    # count w A_T / A_S. Each is traced from upstream onto the module boxes.
    RT = hdiag * (1 + tanα) + 0.05
    n = rand(rng, Poisson(ev.weight * π * RT^2 / R.area))
    n == 0 && return
    t_x = p.time + t * u"m" / p.speed
    L = hdiag / abs(da) + 1.0
    for _ in 1:n
        r, φ = RT * sqrt(rand(rng)), 2π * rand(rng)
        q = c .+ (r * cos(φ) .* e1 .+ r * sin(φ) .* e2) .* u"m"
        start = q .- d .* (L * u"m")
        ixs = intersect_all(det_bvh, Ray(Coordinate(start, cs), p.direction))
        isempty(ixs) && continue
        ix = first(ixs)
        ix.index == k || continue
        # The box straddles the terrain surface. A real particle could not enter
        # its buried half, because it would have stopped at the ground first. So
        # the entry point must see sky upstream (same rock budget, over 2 m).
        upstream = Ray(ix.point, Direction(-d, cs))
        rock_traversed(upstream, topo_bvh; cap = 2.0u"m")[2] > max_rock && continue
        time = t_x + (ix.distance - L * u"m") / p.speed
        push!(hits, (particle = Particle(p.pdg, p.energy, ix.point, p.direction, time, p.speed),
                     module_index = k, weight = 1.0))
    end
    return
end

# All hits of one event dir with de-thinning. Showers are read one at a time,
# because resampling is done per shower axis.
function _dethinned_event_hits(event_dir, cs, units, det_bvh, topo_bvh; seed, kwargs...)
    showers = _corsika_showers(event_dir, cs)
    isempty(showers) && throw(ArgumentError("No completed showers found in $event_dir"))
    hits = CorsikaHitRec[]
    for s in showers
        # Streamed: only the thinned particles are held in memory.
        events = MultiParquetIterator([s.file], Function[s.transform]; T = CorsikaEvent)
        shower_seed = _dethin_seed(seed, _stable_path_key(s.shower_dir))
        append!(hits, resample_shower_hits(shower_seed, events,
                                           () -> corsika_shower_axis(s.shower_dir, cs),
                                           units, det_bvh, topo_bvh; kwargs...))
    end
    return hits
end

_dethin_seed(seed, key) = ((seed % UInt64) * 0x9e3779b97f4a7c15) ⊻ key
