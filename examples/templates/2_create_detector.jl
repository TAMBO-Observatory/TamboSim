# 2_create_detector.jl
#
# Place detector units (OBBs) on a single GC bundle and write them back into
# the D frame. The modules are laid out on a hexagonal grid projected onto
# the detector surface triangles, with a max-slope filter that skips
# near-vertical patches. The placement algorithm itself lives in TamboSim
# proper as `TamboSim.place_detector_units`; this script is just a thin CLI
# around it.
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
default_geometry_jld2 = joinpath(tambo_path, "examples", "output", "geometry", "custom_site.jld2")

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
using TamboSim
using Unitful

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
            default = default_geometry_jld2
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

isfile(infile) || error(
    """
    GC bundle JLD2 not found: $infile

    Run examples/templates/1_create_geometry.jl first to produce it (or pass
    an explicit --input path).
    """
)

frames = load_frames(infile)
g_frame = frames.g_frames[end]
d_frame = frames.d_frames[end]

obbs, obb_bvh = place_detector_units(g_frame, d_frame; spacing=spacing, max_slope_deg=slope)

if isempty(obbs)
    error("No detector units survived placement — check --spacing ($(args["spacing"]) m) and --slope ($(slope)°) against your geometry.")
end

d_frame["detector_units"]    = obbs
d_frame["detector_unit_bvh"] = obb_bvh

save_frames(outfile, frames, streams=('G', 'C', 'D'))

sz_mb = round(filesize(outfile) / 1024^2, digits=1)
println("Placed $(length(obbs)) modules (spacing $(args["spacing"]) m, max slope $(slope)°)")
println("  $infile → $outfile  ($sz_mb MB)")
