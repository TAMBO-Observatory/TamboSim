# add_detector_units_batch.jl
#
# TamboSim-collab batch op: for each candidate_site_*.jld2 in resources/geometry/,
# place detector units (OBBs) and write them back into the D frame in place.
# Thin wrapper around `TamboSim.place_detector_units` over a list of sites.
#
# For single-site placement (external-user / per-site workflow) see the
# template at examples/templates/2_create_detector.jl.
#
# Keys added to each D frame:
#   "detector_units"     — Vector{OBB{Float64}}, one per module
#   "detector_unit_bvh"  — BVHTree over those OBBs (for fast hit queries)

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using TamboSim
using Unitful

const GEO_DIR   = joinpath(tambo_path, "resources", "geometry")
const SPACING   = 125.0u"m"
const MAX_SLOPE = parse(Float64, get(ENV, "MAX_SLOPE_DEG", "35"))  # degrees

site_files = sort(filter(f -> startswith(basename(f), "candidate_site_"), readdir(GEO_DIR, join=true)))

println("Adding detector units to $(length(site_files)) candidate site GCD bundles (spacing $SPACING, max slope $(MAX_SLOPE)°)\n")

for jld2_path in site_files
    site = replace(basename(jld2_path), ".jld2" => "")
    frames = load_frames(jld2_path)
    g_frame = frames.g_frames[end]
    d_frame = frames.d_frames[end]

    obbs, obb_bvh = place_detector_units(g_frame, d_frame; spacing=SPACING, max_slope_deg=MAX_SLOPE)

    if isempty(obbs)
        @warn "$site: 0 modules placed (skipping write)"
        continue
    end

    d_frame["detector_units"]    = obbs
    d_frame["detector_unit_bvh"] = obb_bvh

    save_frames(jld2_path, frames, streams=('G', 'C', 'D'))

    sz_mb = round(filesize(jld2_path) / 1024^2, digits=1)
    println("  $site: $(length(obbs)) modules → $(sz_mb) MB")
end

println("\nDone.")
