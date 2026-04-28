tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using LinearAlgebra
using Rotations
using Tambo
using Unitful
using Printf

const GEO_DIR      = joinpath(tambo_path, "resources", "geometry")
const HALF_LENGTHS = [1.0u"m", 1.0u"m", 0.125u"m"]
const GRID_MARGIN  = 500.0u"m"
const MAX_SLOPE    = parse(Float64, get(ENV, "MAX_SLOPE_DEG", "35"))

function count_modules(g_frame::Frame, d_frame::Frame, Δy::typeof(1.0u"m"); max_slope_deg=MAX_SLOPE)
    cs  = g_frame["cs"]
    bvh = d_frame["detector_bvh"]
    det_triangles = bvh.triangles

    areas     = ustrip.(u"m^2", Tambo.area.(det_triangles))
    centroids = [ustrip.(u"m", (t.v1.point + t.v2.point + t.v3.point) ./ 3)
                 for t in det_triangles]
    normals   = [Tambo.normal(t).point for t in det_triangles]
    total_a   = sum(areas)
    wn = sum(a .* n for (a, n) in zip(areas, normals))

    direction = Tambo.Direction(wn, cs)
    n_vec = direction.point
    nx, ny, nz = n_vec[1], n_vec[2], n_vec[3]
    Δx      = (nz / sqrt(nx^2 + nz^2)) * Δy
    Δy_grid = (nz / sqrt(ny^2 + nz^2)) * Δy * sqrt(3) / 2

    up = Tambo.Direction([0.0, 0.0, 1.0], cs)

    xs_raw = [c[1] for c in centroids] .* u"m"
    ys_raw = [c[2] for c in centroids] .* u"m"
    x_lo = minimum(xs_raw) - GRID_MARGIN
    x_hi = maximum(xs_raw) + GRID_MARGIN
    y_lo = minimum(ys_raw) - GRID_MARGIN
    y_hi = maximum(ys_raw) + GRID_MARGIN

    base_xs = collect(x_lo:Δx:x_hi)
    base_ys = collect(y_lo:Δy_grid:y_hi)

    max_slope_rad = deg2rad(max_slope_deg)
    count = 0
    for (idx, y) in enumerate(base_ys)
        xoffset = mod(idx, 2) == 0 ? 0.0u"m" : Δx / 2
        xs = base_xs .+ xoffset
        coords = [Tambo.Coordinate(x, y, 0.0u"m", cs) for x in xs]
        rays   = Tambo.Ray.(coords, Ref(up))
        for ray in rays
            ixs = Tambo.intersect_all(bvh, ray)
            isempty(ixs) && continue
            ψ = acos(clamp(dot(ixs[1].normal, up), -1.0, 1.0))
            ψ > max_slope_rad && continue
            count += 1
        end
    end
    return count
end

spacings = [150.0u"m", 125.0u"m", 100.0u"m"]
site_files = sort(filter(f -> startswith(basename(f), "candidate_site_"), readdir(GEO_DIR, join=true)))

results_cut   = Dict{String, Vector{Int}}()
results_nocut = Dict{String, Vector{Int}}()

for jld2_path in site_files
    site = replace(basename(jld2_path), ".jld2" => "")
    frames = load_frames(jld2_path)
    g_frame = Tambo._get_last_frame(frames, 'G')
    d_frame = Tambo._get_last_frame(frames, 'D')
    results_cut[site]   = [count_modules(g_frame, d_frame, s; max_slope_deg=MAX_SLOPE) for s in spacings]
    results_nocut[site] = [count_modules(g_frame, d_frame, s; max_slope_deg=90.0)      for s in spacings]
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
