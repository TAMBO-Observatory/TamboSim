# 6_corsika_hits.jl
#
# Read the per-event CORSIKA output directories produced by 5_run_corsika.jl
# and project each surviving shower particle onto the detector OBBs in the
# D frame. For every particle that hits a module, record a corrected
# Particle (drifted to the OBB intersection point), the module index, and
# the CORSIKA event weight.
#
# Input:
#   <geometry>.jld2     GCD bundle containing detector units in the D frame
#                       (`detector_unit_bvh`) — produced by running
#                       2_create_detector.jl on the output of
#                       1_create_geometry.jl
#   <infile>.jld2       Q-frame stream from 5_run_corsika.jl, where each
#                       Q frame's `event_id` matches a `<corsika-dir>/event_<id>/`
#                       directory
#   <corsika-dir>/      directory of per-event tambo_shower output read via
#                       `Tambo.read_corsika`
#
# Output:
#   <outfile>.jld2      the same Q-frame stream with a new key
#                       `corsika_hits`: a Vector of NamedTuples
#                       (particle, module_index, weight), one per hit
#
# Geometry note: each detector OBB straddles its terrain triangle by
# ±DETECTOR_HEIGHT, so a CORSIKA particle recorded at that triangle lies inside
# the module's volume. `intersect_module_signed` drifts the particle
# backward along its trajectory to the entry face (sky side) of the OBB,
# which gives a consistent "when did this particle enter the detector"
# timestamp. The forward-ray branch is a fallback for floating-point
# edge cases and the rare event where the recorded crossing and the hit
# module are on adjacent triangles.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using ProgressMeter
using Tambo

function intersect_module_signed(event, bvh)
    ray = Tambo.Ray(event.particle)
    ixs = Tambo.intersect_all(bvh, reverse(ray))
    length(ixs)==0 || return (last(ixs), -1)
    ixs = Tambo.intersect_all(bvh, ray)
    length(ixs)==0 || return (first(ixs), +1)
    return nothing
end

# =============================================================================
# Main
# =============================================================================

function parse_commandline()
    s = ArgParseSettings(
        description = "Project CORSIKA shower particles onto detector OBBs and record hits"
    )

    @add_arg_table! s begin
        "--geometry", "-g"
            help = "Path to GCD bundle JLD2 with detector units placed (from 2_create_detector.jl)"
            arg_type = String
            default = "$(tambo_path)/resources/geometry/colca_valley_3000.jld2"
        "--infile", "-i"
            help = "Input JLD2 with CORSIKA-ready frames (from 5_run_corsika.jl)"
            arg_type = String
            default = "$(tambo_path)/examples/output/corsika_ready.jld2"
        "--corsika-dir", "-d"
            help = "Directory containing per-event tambo_shower output dirs"
            arg_type = String
            default = "$(tambo_path)/examples/output/corsika"
        "--outfile", "-o"
            help = "Output JLD2 file path (defaults to overwriting --infile)"
            arg_type = String
            default = ""
    end

    return parse_args(s)
end

args = parse_commandline()

geometry_file = args["geometry"]
infile        = args["infile"]
corsika_dir   = args["corsika-dir"]
outfile       = isempty(args["outfile"]) ? infile : args["outfile"]

frames = Tambo.load_frames([geometry_file, infile])
gframe = frames.g_frames[end]
dframe = frames.d_frames[end]
q_frames = filter(f -> f.stream == 'Q', frames)

cs = gframe["cs"]

haskey(dframe, "detector_unit_bvh") || error(
    """
    D frame does not contain "detector_unit_bvh".

    This script requires the input GCD bundle to have detector units already
    placed in its D frame. Run examples/templates/2_create_detector.jl on
    $geometry_file before re-running this script.
    """
)
detector_unit_bvh = dframe["detector_unit_bvh"]

@showprogress for frame in q_frames
    d = "$(corsika_dir)/event_$(lpad(frame["event_id"], 6, "0"))/"
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
    frame["corsika_hits"] = q
end

mkpath(dirname(outfile))
Tambo.save_frames(outfile, frames)
println("Saved → $outfile")
