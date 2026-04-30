# count_detector_units.jl
#
# Tambo-collab site survey: for each candidate_site_*.jld2 in
# resources/geometry/, count how many detector OBBs would be placed at
# each of several module spacings, both with and without the standard
# slope filter. Print a per-site table.
#
# Wraps `Tambo.place_detector_units` and reports `length(obbs)`. The full
# OBB list is built and discarded for each (site, spacing) pair — fine
# for an offline survey, not what you want in a hot loop.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using Tambo
using Unitful
using Printf

const GEO_DIR   = joinpath(tambo_path, "resources", "geometry")
const MAX_SLOPE = parse(Float64, get(ENV, "MAX_SLOPE_DEG", "35"))

count_modules(gframe, dframe, spacing; max_slope_deg=MAX_SLOPE) =
    length(place_detector_units(gframe, dframe; spacing=spacing, max_slope_deg=max_slope_deg)[1])

spacings = [150.0u"m", 125.0u"m", 100.0u"m"]
site_files = sort(filter(f -> startswith(basename(f), "candidate_site_"), readdir(GEO_DIR, join=true)))

results_cut   = Dict{String, Vector{Int}}()
results_nocut = Dict{String, Vector{Int}}()

for jld2_path in site_files
    site = replace(basename(jld2_path), ".jld2" => "")
    frames = load_frames(jld2_path)
    gframe = frames.g_frames[end]
    dframe = frames.d_frames[end]
    results_cut[site]   = [count_modules(gframe, dframe, s; max_slope_deg=MAX_SLOPE) for s in spacings]
    results_nocut[site] = [count_modules(gframe, dframe, s; max_slope_deg=90.0)      for s in spacings]
end

println()
println("| Site              |       150 m       |       125 m       |       100 m       |")
println("|-------------------|------------------:|------------------:|------------------:|")
totals_cut   = zeros(Int, 3)
totals_nocut = zeros(Int, 3)
for jld2_path in site_files
    site = replace(basename(jld2_path), ".jld2" => "")
    c  = results_cut[site]
    nc = results_nocut[site]
    @printf("| %-17s | %4d (%4d) | %4d (%4d) | %4d (%4d) |\n",
            site, c[1], nc[1], c[2], nc[2], c[3], nc[3])
    totals_cut   .+= c
    totals_nocut .+= nc
end
println("|-------------------|------------------:|------------------:|------------------:|")
@printf("| %-17s | %3d (%3d) | %3d (%3d) | %3d (%3d) |\n",
        "Total", totals_cut[1], totals_nocut[1],
                 totals_cut[2], totals_nocut[2],
                 totals_cut[3], totals_nocut[3])
