module TamboSim

export PhaseSpace,
       PhaseSpacePoint,
       NeutrinoInjectionPS,
       ForcedNeutrinoInteractionPoint,
       UpstreamNeutrinoInteractionPoint,
       CosmicRayInjectionPS,
       SurfaceCRPoint,
       oneweight,
       oneweights,
       oneweights!,
       Ray,
       Coordinate,
       Direction,
       intersect_all,
       Frame,
       TamboFrames,
       frames_of_stream,
       hierarchy_violations,
       is_valid_hierarchy,
       inject!,
       proposal_propagation!,
       save_frames,
       load_frames,
       ecefcoordinates,
       get_tambosim_path,
       get_git_commit_hash,
       get_git_tag,
       is_git_dirty,
       get_version_string,
       relativize!,
       upwards_ray_at,
       is_above_topography,
       place_detector_units,
       nucleus_pdg,
       # CORSIKA orchestration
       corsika_run!,
       plan_corsika_jobs,
       build_corsika_argv,
       run_local,
       run_sbatch,
       dump_to_file,
       collect_jobs,
       read_corsika_hits!,
       # Llama progress utilities
       print_llama,
       llama_progress,
       @llama_showprogress,
       LlamaBarGlyphs


using Arrow
using CoordinateTransformations
using Dierckx: Spline1D, Spline2D
using Distributions: Uniform, Poisson
using Glob
using HDF5
using Integrals
using JLD2: jldopen, JLDFile, load
using JSON3
using LibGit2
using LinearAlgebra
using Parquet2
using PrecompileTools
using Printf: @sprintf
using ProgressMeter
using Random
using Rotations
using SHA: sha256
using StaticArrays
using StatsBase
using Tables
using TOML
using Unitful
using YAML

include("units.jl")
include("llama_progress.jl")
include("frames/frames.jl")
include("geometry/geometry.jl")
include("ray_tracing/ray_tracing.jl")
include("samplers/samplers.jl")
include("weighting/weighting.jl")
include("particles/particles.jl")
include("injection/injection.jl")
include("julia_interfaces/julia_interfaces.jl")
include("corsika/corsika.jl")
include("utils.jl")
include("geometry_queries.jl")

"""
    __init__()

Initializes the TamboSim module.
"""
function __init__()

    if isinteractive()
        println(raw"""

  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓  ▓▓  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓     █   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓         ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓        ▓▓▓▓▓▓▓▓▓▓▓▓▓▓    ▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓          ▒▒▒▒▒▒▒▒▒        ▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓          ▒▒▒ ▒  ▒▒      ▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓          ▒▒▒▒  ▒▒▒      ▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓         ▒▒▒▒▒▒▒▒▒      ▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓                       ▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓           ▓▓       ▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   ▓   ▓▓▓▓▓▓  ▓  ▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ▓▓  ▓▓▓▓▓▓▓  ▓  ▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ▓▓  ▓▓▓▓▓▓▓  ▓  ▓▓▓▓▓▓▓▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

  ████████╗ █████╗ ███╗   ███╗██████╗  ██████╗
  ╚══██╔══╝██╔══██╗████╗ ████║██╔══██╗██╔═══██╗
     ██║   ███████║██╔████╔██║██████╔╝██║   ██║
     ██║   ██╔══██║██║╚██╔╝██║██╔══██╗██║   ██║
     ██║   ██║  ██║██║ ╚═╝ ██║██████╔╝╚██████╔╝
     ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═════╝  ╚═════╝
                                                     """)
    end

    try
        tr_init()
    catch e
        @warn "TauRunner could not be loaded. Injection not possible" exception=(e, catch_backtrace())
    end

    try
        tag = get_git_tag()
        if tag !== nothing
            println("Version: $tag")
        else
            hash = something(get_git_commit_hash(), "unknown")
            println("Git commit hash: $hash")
        end
        if is_git_dirty()
            @warn "Working tree has uncommitted changes — version label may be inaccurate"
        end
    catch
        println("Git commit hash: unknown")
    end
end

# Custom display methods for TamboSim types (must be at end after all types are defined)
include("display.jl")

# Precompilation workloads to reduce time-to-first-use latency
@setup_workload begin
    @compile_workload begin
        # Geometry primitives
        cs = ecefcoordinates
        c1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
        c2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
        c3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
        c4 = Coordinate([0.0u"m", 0.0u"m", 1.0u"m"], cs)

        d = Direction([0.0, 0.0, 1.0], cs)
        revd = reverse(d)

        # Triangle operations
        tri = Triangle(c1, c2, c3)
        n = normal(tri)
        a = area(tri)
        cent = centroid(tri)

        # Multiple triangles for BVH
        tri2 = Triangle(c1, c2, c4)
        tri3 = Triangle(c2, c3, c4)
        triangles = [tri, tri2, tri3]

        # BVH construction and intersection
        bvh = BVHTree(triangles)
        ray = Ray(Coordinate([0.1u"m", 0.1u"m", -1.0u"m"], cs), d)
        find_intersect(ray, bvh)
        intersect_all(bvh, ray)

        # AABB operations
        aabb = AABB(tri)
        aabb2 = AABB(tri2)
        merged = merge(aabb, aabb2)

        # Sphere operations
        sphere = Sphere(c1, 1.0u"m")
        intersect_all(sphere, ray)

        # Samplers
        pl = UnitfulPowerLawSampler(-2.0, 1e3u"GeV", 1e6u"GeV")
        rand(pl)

        as = UniformAngularSampler(0.0, π/2, 0.0, 2π)
        rand(as, cs)

        # Particles
        p = Particle(ParticleType(16), 1e5u"GeV", c1, d)

        # Detector culling operations
        normals = normal.(triangles)
        faces_forward(d, normals[1])
        verts, faces = triangles_to_mesh(triangles)
        compute_occlusion(verts, faces, d, bvh)
        geometric_triangle_weight(triangles, d, normals, bvh)
    end
end

end # module
