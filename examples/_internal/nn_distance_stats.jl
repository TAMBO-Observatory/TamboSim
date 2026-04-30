tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using LinearAlgebra
using Statistics
using Tambo
using Unitful
using Printf

const GEO_DIR = joinpath(tambo_path, "resources", "geometry")

function nn_distances(obbs)
    pts = [ustrip.(u"m", o.center.point) for o in obbs]
    dists = Float64[]
    for i in eachindex(pts)
        best = Inf
        for j in eachindex(pts)
            i == j && continue
            d = norm(pts[i] .- pts[j])
            d < best && (best = d)
        end
        push!(dists, best)
    end
    return dists
end

site_files = sort(filter(f -> startswith(basename(f), "candidate_site_"), readdir(GEO_DIR, join=true)))

println("| Site             | N modules | Mean NN dist (m) | Std (m) |")
println("|------------------|----------:|-----------------:|--------:|")

for jld2_path in site_files
    site = replace(basename(jld2_path), ".jld2" => "")
    frames = load_frames(jld2_path)
    d_frame = frames.d_frames[end]
    obbs   = d_frame["detector_units"]
    dists  = nn_distances(obbs)
    @printf("| %-16s |       %3d |           %6.2f |   %5.2f |\n",
            site, length(obbs), mean(dists), std(dists))
end
