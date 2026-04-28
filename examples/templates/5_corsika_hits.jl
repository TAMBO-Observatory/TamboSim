using JLD2
using LinearAlgebra
using ProgressMeter
using Rotations
using Tambo
using Unitful

basedir = ARGS[1]
gc_file = length(ARGS) >= 2 ? ARGS[2] : joinpath(basedir, "gc_frames.jld2")

function intersect_module_signed(event, bvh)
    ray = Tambo.Ray(event.particle)
    ixs = Tambo.intersect_all(bvh, reverse(ray))
    length(ixs)==0 || return (last(ixs), -1)
    ixs = Tambo.intersect_all(bvh, ray)
    length(ixs)==0 || return (first(ixs), +1)
    return nothing
end

frames = Tambo.load_frames([gc_file, "$(basedir)/simfile_corsika.jld2"])
gframe = Tambo._get_last_frame(frames, 'G')
dframe = Tambo._get_last_frame(frames, 'D')
q_frames = filter(f -> f.stream == 'Q', frames)

cs = gframe["cs"]

haskey(dframe, "detector_unit_bvh") || error(
    """
    D frame does not contain "detector_unit_bvh".

    This script requires the input GC bundle to have detector units already
    placed in its D frame. Run a detector-placement step on $gc_file before
    re-running this script — see examples/_internal/add_detector_units.jl
    (or examples/templates/2_create_detector.jl, when available).
    """
)
detector_unit_bvh = dframe["detector_unit_bvh"]

@showprogress for frame in q_frames
    d = "$(basedir)/event_$(lpad(frame["event_id"], 6, "0"))/"
    q = NamedTuple{(:particle, :module_index, :weight), Tuple{Tambo.Particle{Float64}, Int, Float64}}[]
    events = nothing
    try
        events = Tambo.read_corsika(d, cs)
    catch
        continue
    end

    for event in events
        result = intersect_module_signed(event, detector_unit_bvh)
        isnothing(result) && continue
        ix, sign = result
        p = event.particle
        corrected_time = p.time + sign * ix.distance / p.speed
        corrected_particle = Tambo.Particle(p.pdg, p.energy, ix.point, p.direction, corrected_time, p.speed)
        push!(q, (particle=corrected_particle, module_index=ix.index, weight=event.weight))
    end
    frame["corsika_hits_corrected"] = q
end

Tambo.save_frames("$(basedir)/simfile_corsika.jld2", frames)
