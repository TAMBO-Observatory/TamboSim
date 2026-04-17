"""
    3D Event Display

    Validates that CORSIKA particle hits lie on the observation plane and
    renders a 3D event display with the mountain terrain, detector region,
    and shower particle hits.

    Usage:
        julia examples/event_display_3d.jl <event_dir> [output.png]

    <event_dir> should contain shower_*/particles/ subdirectories
    (i.e. point to one event directory, e.g. .../test/event_000001/).
"""

import Pkg
Pkg.activate(joinpath(dirname(@__DIR__)))

using Tambo
import Tambo: CoordinateSystem, CorsikaEvent, read_corsika
using CairoMakie
using CairoMakie.Makie.GeometryBasics: Point3f, TriangleFace, normal_mesh
using Unitful: ustrip, @u_str
using LinearAlgebra
using Statistics
using Parquet2
using Tables
using Glob

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
event_dir = length(ARGS) >= 1 ? ARGS[1] : error("Usage: julia event_display_3d.jl <event_dir> [output.png]")
outpath   = length(ARGS) >= 2 ? ARGS[2] : joinpath(dirname(event_dir), "event_display_3d.png")

earth_path   = joinpath(dirname(@__DIR__), "resources", "basic_geometry.h5")
earth_loc    = "$earth_path:colca_valley_30000"
detector_key = "detector1"
filter_radius = 15_000.0  # metres around detector centre

# ---------------------------------------------------------------------------
# Load geometry
# ---------------------------------------------------------------------------
println("Loading Earth geometry…")
earth = Earth(earth_loc, detector_key)
cs    = CoordinateSystem(earth)

function tri_centroid(tri)
    v1 = ustrip.(u"m", tri.v1.point)
    v2 = ustrip.(u"m", tri.v2.point)
    v3 = ustrip.(u"m", tri.v3.point)
    return (v1 .+ v2 .+ v3) ./ 3
end

det_tris     = earth.topography[earth.detector_region]
det_center   = mean(tri_centroid.(det_tris))
println("Detector centre (ENU, m): ", round.(det_center, digits=1))

function within_radius(tri, center, r)
    c = tri_centroid(tri)
    return sqrt((c[1]-center[1])^2 + (c[2]-center[2])^2) <= r
end

nearby = findall(t -> within_radius(t, det_center, filter_radius), earth.topography)
det_set = Set(earth.detector_region)
println("Triangles within $(filter_radius/1000) km: $(length(nearby))")

# ---------------------------------------------------------------------------
# Load CORSIKA particle hits
# ---------------------------------------------------------------------------
println("Reading CORSIKA particles from $event_dir …")
events = CorsikaEvent[]
for evt in read_corsika(event_dir, cs)
    push!(events, evt)
end
println("Particles: $(length(events))")

# ---------------------------------------------------------------------------
# Validate: check that all particles have z ≈ 0 in shower-plane coordinates.
# The raw parquet column `z` is the shower-plane perpendicular distance, which
# should be exactly 0 for particles that hit the observation plane.
# ---------------------------------------------------------------------------
hit_positions = [ustrip.(u"m", e.particle.position.point) for e in events]

parquet_files = glob("shower_*/particles/particles.parquet", event_dir)
println("\n=== Plane validation (shower-plane z coordinates) ===")
if !isempty(parquet_files)
    all_z = Float64[]
    for pf in parquet_files
        tbl = Parquet2.Dataset(pf)
        for batch in tbl
            append!(all_z, Tables.getcolumn(batch, :z))
        end
    end
    z_mm = all_z .* 1000
    println("Shower-plane z range: $(round(minimum(z_mm), sigdigits=3)) – $(round(maximum(z_mm), sigdigits=3)) mm")
    println("Off-plane residual: mean=$(round(mean(z_mm), sigdigits=3)) mm  std=$(round(std(z_mm), sigdigits=3)) mm  max|z|=$(round(maximum(abs.(z_mm)), sigdigits=3)) mm")
    if maximum(abs.(z_mm)) < 1.0
        println("PASS: all particles within 1 mm of observation plane")
    else
        println("WARN: some particles deviate > 1 mm from observation plane")
    end
else
    println("No particles.parquet files found under $event_dir; skipping validation")
end

# ---------------------------------------------------------------------------
# Build terrain mesh (relative to detector centre)
# ---------------------------------------------------------------------------
vertices = Point3f[]
faces    = TriangleFace{Int}[]
colors   = Float32[]

for idx in nearby
    tri = earth.topography[idx]
    v1 = ustrip.(u"m", tri.v1.point) .- det_center
    v2 = ustrip.(u"m", tri.v2.point) .- det_center
    v3 = ustrip.(u"m", tri.v3.point) .- det_center
    base = length(vertices)
    push!(vertices, Point3f(v1...), Point3f(v2...), Point3f(v3...))
    push!(faces, TriangleFace(base+1, base+2, base+3))
    c = Float32(idx in det_set ? 1.0 : 0.0)
    push!(colors, c, c, c)
end

# ---------------------------------------------------------------------------
# Particle hit positions and energies (relative to detector centre)
# ---------------------------------------------------------------------------
hit_xy  = [ustrip.(u"m", e.particle.position.point)[1:2] .- det_center[1:2] for e in events]
hit_e   = [ustrip(u"GeV", e.particle.energy) for e in events]
hit_w   = [e.weight for e in events]
hit_pdg = [e.particle.pdg for e in events]

is_mu   = (hit_pdg .== Tambo.MuMinus) .| (hit_pdg .== Tambo.MuPlus)
is_em   = (hit_pdg .== Tambo.Gamma)   .| (hit_pdg .== Tambo.EMinus) .| (hit_pdg .== Tambo.EPlus)

# z coordinate of hit plane relative to detector centre
z_plane = mean(p[3] for p in hit_positions) - det_center[3]

hit_pts     = [Point3f(p[1], p[2], z_plane) for p in hit_xy]
hit_pts_mu  = hit_pts[is_mu]
hit_pts_em  = hit_pts[is_em]
hit_pts_had = hit_pts[.!(is_mu .| is_em)]

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
fig = Figure(size=(900, 700))
ax  = Axis3(fig[1, 1];
    xlabel="East [m]", ylabel="North [m]", zlabel="Up [m]",
    azimuth=deg2rad(-65), elevation=deg2rad(22),
    aspect=:data)

# Terrain mesh
m = normal_mesh(vertices, faces)
mesh!(ax, m; color=colors, colormap=[:gray80, :dodgerblue],
      colorrange=(0, 1), shading=Makie.automatic)

# Particle hits (EM: orange, muons: red, hadrons: green)
if !isempty(hit_pts_em)
    scatter!(ax, hit_pts_em; markersize=3, color=(:orange, 0.6), label="EM (γ,e±)")
end
if !isempty(hit_pts_mu)
    scatter!(ax, hit_pts_mu; markersize=5, color=(:red, 0.8), label="µ±")
end
if !isempty(hit_pts_had)
    scatter!(ax, hit_pts_had; markersize=4, color=(:limegreen, 0.7), label="Hadrons")
end

axislegend(ax; position=:rt)

title_str = "Event display — $(length(events)) particles"
Label(fig[0, 1], title_str; fontsize=16, tellwidth=false)

save(outpath, fig, px_per_unit=3)
println("\nSaved to $outpath")
