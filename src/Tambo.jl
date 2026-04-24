module Tambo

export Ray,
       Coordinate,
       Direction,
       intersect_all,
       Frame,
       inject!,
       inject_protons!,
       proposal_propagation!,
       cut_frames!,
       load_config,
       load_earth!,
       save_frames,
       load_frames,
       get_frame,
       ecefcoordinates,
       get_tambosim_path,
       get_git_commit_hash,
       get_version_string,
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
using ProgressMeter
using Random
using Rotations
using StaticArrays
using StatsBase
using Tables
using TOML
using Unitful
using YAML

include("units.jl")
include("geometry/geometry.jl")
include("ray_tracing/ray_tracing.jl")
include("samplers/samplers.jl")
include("weighting/weighting.jl")
include("particles/particles.jl")
include("injection/injection.jl")
include("julia_interfaces/julia_interfaces.jl")
include("corsika/corsika.jl")
include("frames/frames.jl")
include("llama_progress.jl")

"""
    get_tambosim_path() -> String

Returns the TAMBO-MC repository root path. Uses the `TAMBOSIM_PATH` environment variable
if set, otherwise infers the path from the location of this source file.
"""
function get_tambosim_path()
    return get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))
end

"""
    __init__()

Initializes the Tambo module.

This function is automatically called when the module is loaded. It retrieves and prints
the Git commit hash of the Tambo repository and displays a welcome message with ASCII art.
"""
function __init__()

    try
        tr_init()
    catch e
        @warn "TauRunner could not be loaded. Injection not possible" exception=(e, catch_backtrace())
    end

    if isinteractive()
        commit_hash = try
            get_git_commit_hash()
        catch e
            "unknown"
        end
        println("Welcome to TAMBOSim version -0.1")
        println("Git commit hash: $commit_hash")
        println(raw"""
                  /\    //\
                 { `---'  }
                 {  O   O  }
          _      {  \     /}     __
        /  \     `._`---'_/     /  \
       /  | \  ν_τ  `~.~`  ν_τ /  | \
      /   |  \     _.-'-.     /   |  \
     /    |   \ .'       `.  /    |   \
    /     |    /           \/     |    \ """)
        println(raw"""
        ████████╗ █████╗ ███╗   ███╗██████╗  ██████╗
        ╚══██╔══╝██╔══██╗████╗ ████║██╔══██╗██╔═══██╗
           ██║   ███████║██╔████╔██║██████╔╝██║   ██║
           ██║   ██╔══██║██║╚██╔╝██║██╔══██╗██║   ██║
           ██║   ██║  ██║██║ ╚═╝ ██║██████╔╝╚██████╔╝
           ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═════╝  ╚═════╝
                                                     """)
    end
end

"""
    get_git_commit_hash() -> String

Retrieves the Git commit hash of the Tambo repository.
"""
function get_git_commit_hash()::Union{String, Nothing}
    try
        repo = LibGit2.GitRepo(get_tambosim_path())
        return LibGit2.string(LibGit2.head_oid(repo))
    catch
        return nothing
    end
end

function get_version_string()
    string(pkgversion(Tambo))
end

"""
    relativize!(d::Dict)

Recursively resolves relative path strings in a dictionary against the package root directory.
Strings containing `/` but not starting with `/` are treated as relative paths.
Also handles the legacy `_TAMBOSIM_PATH_` placeholder for backward compatibility.

This function modifies the dictionary in-place.

# Arguments
- `d::Dict`: The dictionary to modify.
"""
function relativize!(d::Dict)
    pkg_root = dirname(@__DIR__)
    tambo_data_path = get(ENV, "TAMBO_DATA_PATH", "")
    tambo_corsika_path = get(ENV, "TAMBO_CORSIKA_PATH", "")
    tambo_flupro_path = get(ENV, "TAMBO_FLUPRO_PATH", "")
    for (k, v) in pairs(d)
        if isa(v, String)
            v_new = replace(v, "_TAMBOSIM_PATH_" => pkg_root)
            v_new = replace(v_new, "_TAMBO_DATA_PATH_" => tambo_data_path)
            v_new = replace(v_new, "_TAMBO_CORSIKA_PATH_" => tambo_corsika_path)
            v_new = replace(v_new, "_TAMBO_FLUPRO_PATH_" => tambo_flupro_path)
            if v_new == v && contains(v, '/') && !startswith(v, '/')
                v_new = joinpath(pkg_root, v)
            end
            d[k] = v_new
        elseif isa(v, Dict)
            relativize!(v)
        end
    end
end

"""
    validate_config_file(config::Dict{String, Any})

Placeholder for configuration validation.
"""
function validate_config_file(config::Dict{String, Any})
    # TODO: Implement configuration validation
end

"""
    load_earth!(gframe::Frame)

Reads geometry from `gframe["earth_path"]` and `gframe["detector_key"]` and
populates the G frame with the following keys:

- `"prem"`: `Vector{Sphere}` — concentric PREM layers for ray tracing
- `"topography"`: `Vector{Triangle}` — surface mesh
- `"bvh"`: `BVHTree` — acceleration structure over the full topography
- `"detector_region"`: `Vector{Int}` — indices of detector-region triangles
- `"cs"`: `CoordinateSystem` — local ENU coordinate system at the site

Dispatches to HDF5 or PLY loading based on the file extension of `earth_path`.
"""
function load_earth!(gframe::Frame)
    location     = gframe["earth_path"]
    detectorname = gframe["detector_key"]
    prem, topography, bvh, detector_region, cs = if endswith(location, ".ply")
        _load_earth_ply(location)
    else
        _load_earth_h5(location, detectorname)
    end
    gframe["prem"]            = prem
    gframe["topography"]      = topography
    gframe["bvh"]             = bvh
    gframe["detector_region"] = detector_region
    gframe["cs"]              = cs
    return gframe
end

CoordinateSystem(gframe::Frame) = gframe["cs"]

"""
    _find_frame(frames::Vector{Frame}, stream::Char) -> Frame

Returns the last frame in `frames` with the given stream type. Errors if none
is found.
"""
function _find_frame(frames::Vector{Frame}, stream::Char)
    idx = findlast(f -> f.stream == stream, frames)
    isnothing(idx) && error("No '$stream' frame found in frame vector")
    return frames[idx]
end

"""
    get_frame(frames::Vector{Frame}, stream::Char) -> Frame

Returns the last frame in `frames` with the given stream type.
"""
get_frame(frames::Vector{Frame}, stream::Char) = _find_frame(frames, stream)

"""
    load_config(config_file::String) -> Vector{Frame}

Parses a TOML configuration file and returns `[G frame, C frame]`.

The G frame holds geometry paths. The C frame holds one key per config section
(e.g. `"injection"`, `"proposal"`, `"corsika"`), with the G frame as its parent.
Paths containing `_TAMBOSIM_PATH_` are resolved to absolute paths.

    load_config(config::Dict) -> Vector{Frame}

Same as above but accepts an already-parsed config dict (useful in tests).
"""
function load_config(config_file::String)
    config = TOML.parsefile(config_file)
    validate_config_file(config)
    relativize!(config)
    return _config_to_frames(config)
end

function load_config(config::Dict)
    config = deepcopy(config)
    relativize!(config)
    return _config_to_frames(config)
end

function _config_to_frames(config::Dict)
    gframe = Frame('G')
    gframe["earth_path"]   = config["geometry"]["earth_path"]
    gframe["detector_key"] = config["geometry"]["detector_key"]
    load_earth!(gframe)

    cframe = Frame('C')
    cframe.parents['G'] = gframe
    for (section, params) in config
        section == "geometry" && continue
        cframe[section] = params
    end

    _check_parent_conflicts(cframe)

    return Frame[gframe, cframe]
end

"""
    _ensure_earth_loaded!(frames::Vector{Frame})

Ensures the G frame has earth geometry loaded. Calls `load_earth!` if prem is missing.
"""
function _ensure_earth_loaded!(frames::Vector{Frame})
    gframe = _find_frame(frames, 'G')
    if !haskey(gframe.data, "prem")
        load_earth!(gframe)
    end
end

"""
    inject!(
        frames::Vector{Frame};
        outprefix::String="injection"
    )

Injects neutrino events into the simulation. Reads configuration from the C frame,
appends one Q frame per event to `frames`, and populates injection states.
"""
function inject!(
    frames::Vector{Frame};
    outprefix::String="injection"
)
    _ensure_earth_loaded!(frames)
    cframe = _find_frame(frames, 'C')
    gframe = _find_frame(frames, 'G')
    cfg = cframe[outprefix]

    prem            = gframe["prem"]
    bvh             = gframe["bvh"]
    cs              = gframe["cs"]
    topography      = gframe["topography"]
    detector_region = gframe["detector_region"]

    q_frames = Frame[]
    q_parents = Dict{Char,Frame}('G' => gframe, 'C' => cframe)
    for idx in 1:cfg["nevent"]
        qframe = Frame('Q', Dict{String,Any}(), q_parents)
        qframe["event_id"] = idx
        push!(q_frames, qframe)
    end
    append!(frames, q_frames)

    pl = UnitfulPowerLawSampler(
        cfg["gamma"],
        cfg["emin"] * u"GeV",
        cfg["emax"] * u"GeV"
    )
    as = UniformAngularSampler(
        deg2rad(cfg["thetamin"]),
        deg2rad(cfg["thetamax"]),
        deg2rad(cfg["phimin"]),
        deg2rad(cfg["phimax"]),
    )
    cross_section = CrossSection(cfg["xs_location"])
    detector_triangles = topography[detector_region]
    detector_bvh   = BVHTree(detector_triangles)
    detector_areas  = area.(detector_triangles)
    detector_normals = normal.(detector_triangles)
    Random.seed!(cfg["pinecone"])

    @llama_showprogress "Injecting" for frame in q_frames
        tr_seed = rand(UInt32)
        istate, cstate, fstate, wp = inject_event(
            cfg["pdg"],
            prem, bvh, cs, detector_region, topography,
            as, pl, cross_section;
            detector_areas=detector_areas,
            detector_normals=detector_normals,
            detector_bvh=detector_bvh,
            tr_seed=tr_seed
        )
        frame["$(outprefix)_initial_state"] = istate
        if !isnan(cstate.energy)
            frame["$(outprefix)_close_state"] = cstate
        end
        if !isnan(fstate.energy)
            frame["$(outprefix)_final_state"] = fstate
        end
        frame["weight_params"] = wp
    end
end

"""
    inject_protons!(
        frames::Vector{Frame};
        outprefix::String="injection"
    )

Injects downgoing cosmic ray protons. Reads configuration from the C frame and
appends one Q frame per event to `frames`.
"""
function inject_protons!(
    frames::Vector{Frame};
    outprefix::String="injection"
)
    _ensure_earth_loaded!(frames)
    cframe = _find_frame(frames, 'C')
    gframe = _find_frame(frames, 'G')
    cfg = cframe[outprefix]

    bvh             = gframe["bvh"]
    cs              = gframe["cs"]
    topography      = gframe["topography"]
    detector_region = gframe["detector_region"]

    q_frames = Frame[]
    q_parents = Dict{Char,Frame}('G' => gframe, 'C' => cframe)
    for idx in 1:cfg["nevent"]
        qframe = Frame('Q', Dict{String,Any}(), q_parents)
        qframe["event_id"] = idx
        push!(q_frames, qframe)
    end
    append!(frames, q_frames)

    pl = UnitfulPowerLawSampler(
        cfg["gamma"],
        cfg["emin"] * u"GeV",
        cfg["emax"] * u"GeV"
    )
    as = UniformAngularSampler(
        deg2rad(cfg["thetamin"]),
        deg2rad(cfg["thetamax"]),
        deg2rad(cfg["phimin"]),
        deg2rad(cfg["phimax"]),
    )
    altitude = get(cfg, "altitude", 50.0) * u"km"
    detector_props = precompute_detector_properties(topography, detector_region)
    Random.seed!(cfg["pinecone"])

    @llama_showprogress "Injecting protons" for frame in q_frames
        initial_proton, final_proton, visible_areas, passes_through_rock = inject_proton_event(bvh, cs, detector_region, as, pl, detector_props; altitude=altitude)
        if !isnan(initial_proton.energy)
            frame["$(outprefix)_initial_state"] = initial_proton
            frame["$(outprefix)_final_state"] = final_proton
            frame["particle_passes_through_rock"] = passes_through_rock
            frame["weight_params"] = WeightParameters(
                sum(visible_areas),
                pl.emin,
                pl.emax,
                pl.γ,
                as.θmin,
                as.θmax,
                as.ϕmin,
                as.ϕmax,
                initial_proton.energy,
                NaN * u"GeV",
                NaN * u"g/cm^2",
                NaN * u"g/cm^3",
                NaN * u"cm^2",
                NaN * u"cm^2",
            )
        end
    end
end

"""
    proposal_propagation!(
        frames::Vector{Frame};
        inkey::String="injection_final_state",
        outprefix::String="proposal"
    )

Propagates particles through the Earth model using PROPOSAL. Operates on all
Q frames in `frames` that contain `inkey`.
"""
function proposal_propagation!(
    frames::Vector{Frame};
    inkey::String="injection_final_state",
    outprefix::String="proposal"
)
    _ensure_earth_loaded!(frames)
    cframe = _find_frame(frames, 'C')
    gframe = _find_frame(frames, 'G')
    cfg = cframe[outprefix]
    init_proposal(cfg)

    prem = gframe["prem"]
    bvh  = gframe["bvh"]

    if haskey(cfg, "pinecone")
        Random.seed!(cfg["pinecone"])
    else
        @warn "Deciding seed via RNG and adding to configuration"
        cfg["pinecone"] = rand(UInt32)
        Random.seed!(cfg["pinecone"])
    end

    q_frames = filter(f -> f.stream == 'Q', frames)

    @llama_showprogress "Propagating" for frame in q_frames
        haskey(frame, inkey) || continue
        final_state = frame[inkey]
        final_state.energy < 106u"MeV" && continue
        ls, contls, decay_products, propped_state = proposal_propagate(
            final_state,
            prem, bvh,
            rand(Int32)
        )
        frame["$(outprefix)_stochastic_losses"] = ls
        frame["$(outprefix)_continuous_losses"] = contls
        frame["$(outprefix)_decay_products"] = decay_products
        frame["$(outprefix)_final_state"] = propped_state
    end
end

"""
    corsika_run(
        frames::Vector{Frame},
        base_outdir;
        inkey::String="proposal_decay_products",
        parallelize=false,
        store_paths=true
    )

Runs CORSIKA for the decay products of events in `frames`. Operates on all
Q frames that contain `inkey`.
"""
function corsika_run(
    frames::Vector{Frame},
    base_outdir;
    inkey::String="proposal_decay_products",
    parallelize=false,
    store_paths=true
)
    _ensure_earth_loaded!(frames)
    cframe = _find_frame(frames, 'C')
    gframe = _find_frame(frames, 'G')
    cfg = cframe["corsika"]

    topography      = gframe["topography"]
    detector_region = gframe["detector_region"]

    obs_mesh_path     = cfg["obs_mesh_path"]
    terrain_mesh_path = get(cfg, "terrain_mesh_path", "")
    hadron_model      = get(cfg, "hadron_model", "SIBYLL-2.3d")
    thinning          = get(cfg, "thinning", 1e-6)

    if haskey(cfg, "pinecone")
        Random.seed!(cfg["pinecone"])
    else
        @warn "Deciding seed via RNG and adding to configuration"
        cfg["pinecone"] = rand(UInt32)
        Random.seed!(cfg["pinecone"])
    end

    sbatch_command = parallelize ? cfg["sbatch_command"] : ""
    ecuts = SVector{3, Float64}([cfg["em_ecut"], cfg["mu_ecut"], cfg["hadron_ecut"]]) * u"GeV"

    for frame in filter(f -> f.stream == 'Q', frames)
        haskey(frame, inkey) || continue
        paths = String[]
        decay_products = frame[inkey]
        for (idx, particle) in enumerate(decay_products)
            abs(Int(particle.pdg)) in [12, 14, 16] && continue
            output_dir = "$(base_outdir)/event_$(lpad(frame["event_id"], 6, '0'))/shower_$(idx)/"
            push!(paths, output_dir)
            isdir(output_dir) && continue
            seed = Int(rand(UInt32))
            try
                corsika_run(
                    particle,
                    topography,
                    detector_region,
                    obs_mesh_path,
                    terrain_mesh_path,
                    ecuts,
                    cfg["corsika_path"],
                    output_dir,
                    seed;
                    thinning=thinning,
                    hadron_model=hadron_model,
                    sbatch_command=sbatch_command
                )
            catch e
                @warn "CORSIKA failed for event $(frame["event_id"]) shower $(idx)" exception=e
            end
        end
        store_paths && (frame["corsika_directories"] = paths)
    end
end

# Custom display methods for Tambo types (must be at end after all types are defined)
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
