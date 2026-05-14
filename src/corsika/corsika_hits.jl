"""
    _corsika_module_hit(event::CorsikaEvent, bvh) -> NamedTuple | nothing

Project a single `CorsikaEvent` onto the detector-unit OBB BVH and
return a hit record `(particle, module_index, weight)`, or `nothing` if
the particle's trajectory does not pass through any module.

Each detector OBB straddles its terrain triangle by ±DETECTOR_HEIGHT, so
a particle recorded at that triangle lies inside the module's volume.
The reverse-ray branch drifts the particle backward to the entry face
(sky side) of the OBB, giving a consistent "when did this particle
enter the detector" timestamp. The forward-ray branch is a fallback for
floating-point edge cases and the rare event where the recorded
crossing and the hit module are on adjacent triangles.
"""
function _corsika_module_hit(event::CorsikaEvent, bvh)
    ray = Ray(event.particle)
    ixs = intersect_all(bvh, reverse(ray))
    if !isempty(ixs)
        ix, sign = last(ixs), -1
    else
        ixs = intersect_all(bvh, ray)
        isempty(ixs) && return nothing
        ix, sign = first(ixs), +1
    end
    p = event.particle
    corrected_time = p.time + sign * ix.distance / p.speed
    corrected_particle = Particle(p.pdg, p.energy, ix.point, p.direction,
                                  corrected_time, p.speed)
    return (particle=corrected_particle,
            module_index=ix.index,
            weight=event.weight)
end

"""
    read_corsika_hits!(frames::TamboFrames, config::Dict=Dict{String,Any}();
                       cs=nothing, prefix::String="corsika_hits") -> nothing

Read CORSIKA shower output for every Q frame stamped with
`q["corsika_directories"]` (by [`corsika_run!`](@ref)), project each
recorded particle onto the detector-unit OBBs in the latest D frame,
and stamp `q["corsika_hits"]` with the resulting hit records.

# Arguments
- `frames`: a `TamboFrames` whose latest M frame's parent G frame
  carries a coordinate system and whose D frame carries
  `"detector_unit_bvh"` (place units via `place_detector_units` /
  `examples/templates/2_create_detector.jl` first).
- `config`: configuration table stamped onto the M frame at
  `m[prefix]` for provenance. Currently no fields are consulted; the
  positional matches the shape of [`corsika_run!`](@ref) and other
  frame-level orchestrators (`inject!`, `proposal_propagation!`).
- `cs`: target `CoordinateSystem` for transformed particle positions.
  Defaults to `m_frame.g_frame["cs"]`.
- `prefix`: M-frame key under which `config` is stamped. Defaults to
  `"corsika_hits"`.

# Behavior
- Q frames missing `"corsika_directories"` are skipped silently.
- Per-shower paths in `corsika_directories` are reduced to their unique
  parent (event-level) dirs before reading; this works because
  `corsika_run!`'s outdir convention places `shower_<n>/` directly
  under `event_<id>/`, and `read_corsika_mesh` expects the event-level
  dir.
- Incomplete showers (missing `summary.yaml`) are skipped per
  `read_corsika_mesh`'s sentinel.

# Output
Stamps each handled Q frame with
`q["corsika_hits"]::Vector{NamedTuple}` of
`(particle::Particle, module_index::Int, weight::Float64)` entries —
one per particle that intersected a detector OBB.
"""
function read_corsika_hits!(
    frames::TamboFrames,
    config::Dict=Dict{String,Any}();
    cs=nothing,
    prefix::String="corsika_hits",
)
    m_frame = _get_last_frame(frames, 'M')
    g_frame = m_frame.g_frame
    d_frame = m_frame.d_frame
    m_frame[prefix] = config

    haskey(d_frame, "detector_unit_bvh") || error(
        "read_corsika_hits!: D frame is missing \"detector_unit_bvh\". " *
        "Run place_detector_units (or examples/templates/2_create_detector.jl) " *
        "on the geometry before calling this function."
    )
    detector_unit_bvh = d_frame["detector_unit_bvh"]

    if isnothing(cs)
        cs = g_frame["cs"]
    end

    HitRec = NamedTuple{(:particle, :module_index, :weight),
                       Tuple{Particle{Float64}, Int, Float64}}

    for q in frames.q_frames
        haskey(q, "corsika_directories") || continue
        event_dirs = unique(dirname.(q["corsika_directories"]))

        hits = HitRec[]
        for d in event_dirs
            isdir(d) || continue
            events = try
                read_corsika_mesh(d, cs)
            catch err
                @warn "read_corsika_hits!: skipping event dir" dir=d exception=err
                continue
            end
            for event in events
                hit = _corsika_module_hit(event, detector_unit_bvh)
                isnothing(hit) || push!(hits, hit)
            end
        end
        q["corsika_hits"] = hits
    end
    return nothing
end
