module Tambo

export Ray,
       Coordinate,
       Direction,
       Earth,
       intersect_all,
       inject!,
       proposal_propagation!,
       proposal_propagation_to_air!,
       corsika_run_from_air,
       cut_frames!,
       Simulation,
       ecefcoordinates,
       get_tambosim_path,
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

This function reads the `TAMBOSIM_PATH` environment variable to find the repository path,
opens the Git repository, and returns the hash of the current HEAD commit.

# Returns
- A string containing the Git commit hash.
"""
function get_git_commit_hash()
    git_repo_path = get_tambosim_path()

    # # Open the Git repository located at the module's directory
    repo = LibGit2.GitRepo(git_repo_path)
            
    # Get the OID (object ID) of the current HEAD reference
    oid = LibGit2.head_oid(repo)
        
    # Convert the OID to a hex string representing the commit hash
    commit_hash = LibGit2.string(oid)
    
    return commit_hash
end


"""
    Simulation

A mutable struct that holds the configuration and results of a Tambo simulation.

# Fields
- `config::Dict{String, Any}`: A dictionary containing the simulation configuration.
- `results::Vector{Frame}`: A vector of `Frame` objects, where each frame represents an event.
"""
mutable struct Simulation
    config::Dict{String, Any}
    results::Vector{Frame}
    function Simulation(config, results)
        @assert "geometry" in keys(config) "Geometry information must be provided"
        return new(config, results)
    end
end

"""
    relativize!(d::Dict)

Recursively replaces the placeholder `_TAMBOSIM_PATH_` in a dictionary with the value
of the `TAMBOSIM_PATH` environment variable.

This function modifies the dictionary in-place.

# Arguments
- `d::Dict`: The dictionary to modify.
"""
function relativize!(d::Dict)
    tambosim_path = get_tambosim_path()
    for (k, v) in pairs(d)
        if isa(v, String)
            d[k] = replace(v, "_TAMBOSIM_PATH_" => tambosim_path)
        elseif isa(v, Dict)
            relativize!(v)
        end
    end
end

"""
    validate_config_file(config::Dict{String, Any})

Placeholder for configuration validation.

This function is intended to ensure that the configuration contains only expected parameters
and that their values are sensible. Currently not implemented.

# Arguments
- `config::Dict{String, Any}`: The configuration dictionary to validate.
"""
function validate_config_file(config::Dict{String, Any})
    # TODO: Implement configuration validation
end

"""
    Simulation(config_file::String) -> Simulation

Constructs a `Simulation` object from a TOML configuration file.

This constructor parses the specified TOML file, validates its contents,
and initializes an empty `Simulation` object with the loaded configuration.
It also calls `relativize!` to make paths in the configuration absolute.

# Arguments
- `config_file::String`: The path to the TOML configuration file.

# Returns
- A new `Simulation` object.
"""
function Simulation(config_file::String)
    config = TOML.parsefile(config_file)
    validate_config_file(config)
    relativize!(config)
    results = Frame[]
    return Simulation(config, results)
end

"""
    inject!(
        sim::Simulation;
        outprefix::String="injection",
        earth::Union{Earth, Nothing}=nothing
    )

Injects particles into the simulation based on the configuration.

This function generates initial neutrino events according to the specified energy and angular distributions.
For each event, it determines the initial, close, and final states of the particle as it interacts
with the provided `Earth` model. The results are stored in the `sim.results` frames.

# Arguments
- `sim::Simulation`: The `Simulation` object to modify.
- `outprefix::String`: A prefix for the keys under which the injection results are stored in the frames. Defaults to "injection".
- `earth::Union{Earth, Nothing}`: An optional `Earth` object. If not provided, it's created from the simulation configuration.
"""
function inject!(
    sim::Simulation;
    outprefix::String="injection",
    earth::Union{Earth, Nothing}=nothing
)
    cfg = sim.config[outprefix]

    relativize!(cfg)
    for idx in 1:cfg["nevent"]
        push!(sim.results, Frame(Dict("event_id"=>idx)))
    end

    if isnothing(earth)
        earth = Earth(
            sim.config["geometry"]["earth_path"],
            sim.config["geometry"]["detector_key"],
        )
    end

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
    detector_bvh = BVHTree(earth.topography[earth.detector_region])
    detector_areas = area.(earth.topography[earth.detector_region])
    detector_normals = normal.(earth.topography[earth.detector_region])
    Random.seed!(cfg["pinecone"])

    is_muon = abs(cfg["nu_pdg"]) == 13
    if is_muon
        detector_props = DetectorProperties(
            earth.topography[earth.detector_region],
            detector_normals,
            detector_bvh,
            detector_areas
        )
    else
        cross_section = CrossSection(cfg["xs_location"])
    end

    @llama_showprogress "Injecting" for frame in sim.results
        tr_seed = rand(UInt32)
        if is_muon
            istate, cstate, fstate, wp = inject_muon_event(
                cfg["nu_pdg"],
                earth,
                as,
                pl,
                detector_props
            )
        else
            istate, cstate, fstate, wp = inject_event(
                cfg["nu_pdg"],
                earth,
                as,
                pl,
                cross_section;
                detector_areas=detector_areas,
                detector_normals=detector_normals,
                detector_bvh=detector_bvh,
                tr_seed=tr_seed
            )
        end
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
    inject_ν!(
        sim::Simulation;
        outprefix::String="injection",
        earth::Union{Earth, Nothing}=nothing
    )

**DEPRECATED**. Use `inject!` instead.

Injects neutrinos into the simulation. This function is an alias for `inject!`.
"""
function inject_ν!(
    sim::Simulation;
    outprefix::String="injection",
    earth::Union{Earth, Nothing}=nothing
)
    @warn("`inject_ν!` is deprecated. Please use `inject!`.")
    inject!(sim; outprefix=outprefix, earth=earth)
end

"""
    proposal_propagation!(
        sim::Simulation;
        inkey::String="injection_final_state",
        outprefix::String="proposal",
        earth::Union{Earth, Nothing}=nothing
    )

Propagates particles through the Earth model using the PROPOSAL library.

This function takes the final state of particles from a previous simulation step (e.g., injection)
and propagates them through the `Earth` model. It calculates and stores stochastic losses,
continuous energy losses, decay products, and the final state of the particle in the `sim.results` frames.

# Arguments
- `sim::Simulation`: The `Simulation` object to modify.
- `inkey::String`: The key for accessing the input particle state in each frame. Defaults to "injection_final_state".
- `outprefix::String`: A prefix for the keys under which the propagation results are stored. Defaults to "proposal".
- `earth::Union{Earth, Nothing}`: An optional `Earth` object. If not provided, it's created from the simulation configuration.
"""
function proposal_propagation!(
    sim::Simulation;
    inkey::String="injection_final_state",
    outprefix::String="proposal",
    earth::Union{Earth, Nothing}=nothing
)
    cfg = sim.config[outprefix]
    relativize!(cfg)
    init_proposal(cfg)

    if haskey(cfg, "pinecone")
        Random.seed!(cfg["pinecone"])
    else
        @warn("Deciding seed via RNG and adding to configuration")
        pinecone = rand(UInt32)
        sim.config[outprefix]["pinecone"] = pinecone
    end
    
    if isnothing(earth)
        earth = Earth(
            sim.config["geometry"]["earth_path"],
            sim.config["geometry"]["detector_key"],
        )
    end


    @llama_showprogress "Propagating" for frame in sim.results
        if !haskey(frame, inkey)
            continue
        end
        final_state = frame[inkey]
        if final_state.energy < 106u"MeV"
            continue
        end
        ls, contls, decay_products, propped_state = proposal_propagate(
            final_state,
            earth,
            rand(Int32)
        )
        frame["$(outprefix)_stochastic_losses"] = ls
        frame["$(outprefix)_continuous_losses"] = contls
        frame["$(outprefix)_decay_products"] = decay_products
        frame["$(outprefix)_final_state"] = propped_state
    end
end

"""
    proposal_propagation_to_air!(
        sim::Simulation;
        inkey::String="injection_final_state",
        outprefix::String="proposal",
        earth::Union{Earth, Nothing}=nothing
    )

Propagates particles through Earth using PROPOSAL, stopping at the last rock→air
interface before the observation plane. If a tau survives to the air boundary, it is
stored as `\$(outprefix)_air_entry_state` in the frame for direct handoff to CORSIKA.

The observation plane is constructed from `sim.config["corsika"]` (plane_coordinates
and plane_orientation).

Stochastic losses, continuous losses, decay products, and the final state are stored
identically to `proposal_propagation!`.

# Arguments
- `sim::Simulation`: The `Simulation` object to modify.
- `inkey::String`: The key for accessing the input particle state in each frame. Defaults to "injection_final_state".
- `outprefix::String`: A prefix for the keys under which the propagation results are stored. Defaults to "proposal".
- `earth::Union{Earth, Nothing}`: An optional `Earth` object.
"""
function proposal_propagation_to_air!(
    sim::Simulation;
    inkey::String="injection_final_state",
    outprefix::String="proposal",
    earth::Union{Earth, Nothing}=nothing
)
    cfg = sim.config[outprefix]
    relativize!(cfg)
    init_proposal(cfg)

    if haskey(cfg, "pinecone")
        Random.seed!(cfg["pinecone"])
    else
        @warn("Deciding seed via RNG and adding to configuration")
        pinecone = rand(UInt32)
        sim.config[outprefix]["pinecone"] = pinecone
    end

    if isnothing(earth)
        earth = Earth(
            sim.config["geometry"]["earth_path"],
            sim.config["geometry"]["detector_key"],
        )
    end

    # Build observation plane from corsika config
    corsika_cfg = sim.config["corsika"]
    relativize!(corsika_cfg)
    cs = CoordinateSystem(earth)
    d = Direction(corsika_cfg["plane_orientation"], ecefcoordinates)
    d = convert(cs, d)
    point = Coordinate(corsika_cfg["plane_coordinates"] .* u"m", ecefcoordinates)
    point = convert(cs, point)
    plane = Plane(point, d)

    @llama_showprogress "Propagating to air" for frame in sim.results
        if !haskey(frame, inkey)
            continue
        end
        final_state = frame[inkey]
        if final_state.energy < 106u"MeV"
            continue
        end
        ls, contls, decay_products, propped_state, air_entry = proposal_propagate_to_air(
            final_state,
            earth,
            plane,
            rand(Int32)
        )
        frame["$(outprefix)_stochastic_losses"] = ls
        frame["$(outprefix)_continuous_losses"] = contls
        frame["$(outprefix)_decay_products"] = decay_products
        frame["$(outprefix)_final_state"] = propped_state
        if !isnothing(air_entry)
            frame["$(outprefix)_air_entry_state"] = air_entry
        end
    end
end

"""
    propagate_τ!(
        sim::Simulation;
        inkey::String="injection_final_state",
        outprefix::String="proposal",
        earth::Union{Earth, Nothing}=nothing
    )

**DEPRECATED**. Use `proposal_propagation!` instead.

Propagates tau leptons through the Earth. This function is an alias for `proposal_propagation!`.
"""
function propagate_τ!(
    sim::Simulation;
    inkey::String="injection_final_state",
    outprefix::String="proposal",
    earth::Union{Earth, Nothing}=nothing
)
    @warn("`propagate_τ!` is deprecated. Please use `proposal_propagation!`.")
    proposal_propagation!(sim; inkey=inkey, outprefix=outprefix, earth=earth)
end

"""
    corsika_run(
        sim::Simulation,
        base_outdir;
        inkey::String="proposal_decay_products",
        earth::Union{Earth, Nothing}=nothing,
        parallelize=false,
        store_paths=true
    )

Runs CORSIKA for the decay products of particles in the simulation.

For each event in the simulation that has decay products, this function initiates
a CORSIKA run for each decay product (that is not a neutrino). It sets up the
CORSIKA environment, defines the observation plane, and then executes the run,
potentially in parallel using a sbatch command.

# Arguments
- `sim::Simulation`: The `Simulation` object.
- `base_outdir`: The base directory where CORSIKA output will be stored.
- `inkey::String`: The key for accessing the decay products in each frame. Defaults to "proposal_decay_products".
- `earth::Union{Earth, Nothing}`: An optional `Earth` object. If not provided, it's created from the simulation configuration.
- `parallelize`: If `true`, submits CORSIKA jobs using the sbatch command specified in the configuration. Defaults to `false`.
- `store_paths`: If `true`, stores the paths to the CORSIKA output directories in the frames. Defaults to `true`.
"""
function corsika_run(
    sim::Simulation,
    base_outdir;
    inkey::String="proposal_decay_products",
    earth::Union{Earth, Nothing}=nothing,
    parallelize=false,
    store_paths=true
)
    cfg = sim.config["corsika"]
    relativize!(cfg)

    if isnothing(earth)

        earth = Earth(
            sim.config["geometry"]["earth_path"],
            sim.config["geometry"]["detector_key"],
        )
    end

    up = Direction([0.0, 0.0, 1.0], CoordinateSystem(earth))

    # Define plane
    d = Tambo.Direction(cfg["plane_orientation"], ecefcoordinates)
    d = convert(CoordinateSystem(earth), d)
    point = Coordinate(cfg["plane_coordinates"] .* u"m", ecefcoordinates)
    point = convert(CoordinateSystem(earth), point)
    plane = Plane(point, d)

    if haskey(cfg, "pinecone")
        Random.seed!(cfg["pinecone"])
    else
        @warn("Deciding seed via RNG and adding to configuration")
        pinecone = rand(UInt32)
        sim.config["corsika"]["pinecone"] = pinecone
    end
    sbatch_command = parallelize ? cfg["sbatch_command"] : ""
    ecuts = SVector{4, Float64}([cfg["em_ecut"], cfg["photon_ecut"], cfg["mu_ecut"], cfg["hadron_ecut"]]) * u"GeV"
    for frame in sim.results
        if !(haskey(frame, inkey))
            continue
        end
        paths = String[]
        decay_products = frame[inkey]
        for (idx, particle) in enumerate(decay_products)
            # Don't run CORSIKA on neutrinos
            if abs(Int(particle.pdg)) in [12,14,16]
                continue
            end

            ray = Ray(particle)
            i, t = find_intersection(ray, plane)
            if isnothing(t)
                continue
            end
            #ray = Ray(particle.position, up)
            #ixs = intersect_all(earth, ray)
            #if length(ixs) > 0
            #    continue
            #end
            output_dir = "$(base_outdir)/event_$(lpad(frame["event_id"], 6, '0'))/shower_$(idx)/"
            push!(paths, output_dir)
            if isdir(output_dir)
                continue
            end
            seed = Int(rand(UInt32))
            try
                corsika_run(
                    particle,
                    plane,
                    cfg["thinning"],
                    ecuts,
                    cfg["corsika_path"],
                    cfg["FLUPRO"],
                    cfg["FLUFOR"],
                    output_dir,
                    seed;
                    sbatch_command=sbatch_command
                )
            catch e
                event_id = frame["event_id"]
                @warn "CORSIKA failed for event $(event_id) shower $(idx)" exception=e
            end
        end
        if store_paths
            frame["corsika_directories"] = paths
        end
    end
end

"""
    corsika_run_from_air(
        sim::Simulation,
        base_outdir;
        inkey::String="proposal_air_entry_state",
        earth::Union{Earth, Nothing}=nothing,
        parallelize=false,
        store_paths=true,
    )

Runs CORSIKA for particles at the air entry point (e.g., taus handed off from PROPOSAL
at the last rock→air interface). Unlike `corsika_run`, this reads a single `Particle`
from `frame[inkey]` rather than iterating over decay products.

# Arguments
- `sim::Simulation`: The `Simulation` object.
- `base_outdir`: The base directory where CORSIKA output will be stored.
- `inkey::String`: The key for accessing the air entry particle in each frame. Defaults to "proposal_air_entry_state".
- `earth::Union{Earth, Nothing}`: An optional `Earth` object.
- `parallelize`: If `true`, submits CORSIKA jobs using sbatch. Defaults to `false`.
- `store_paths`: If `true`, stores output paths in the frames. Defaults to `true`.
"""
function corsika_run_from_air(
    sim::Simulation,
    base_outdir;
    inkey::String="proposal_air_entry_state",
    earth::Union{Earth, Nothing}=nothing,
    parallelize=false,
    store_paths=true,
)
    cfg = sim.config["corsika"]
    relativize!(cfg)

    if isnothing(earth)
        earth = Earth(
            sim.config["geometry"]["earth_path"],
            sim.config["geometry"]["detector_key"],
        )
    end

    # Define plane
    d = Tambo.Direction(cfg["plane_orientation"], ecefcoordinates)
    d = convert(CoordinateSystem(earth), d)
    point = Coordinate(cfg["plane_coordinates"] .* u"m", ecefcoordinates)
    point = convert(CoordinateSystem(earth), point)
    plane = Plane(point, d)

    if haskey(cfg, "pinecone")
        Random.seed!(cfg["pinecone"])
    else
        @warn("Deciding seed via RNG and adding to configuration")
        pinecone = rand(UInt32)
        sim.config["corsika"]["pinecone"] = pinecone
    end
    sbatch_command = parallelize ? cfg["sbatch_command"] : ""
    ecuts = SVector{4, Float64}([cfg["em_ecut"], cfg["photon_ecut"], cfg["mu_ecut"], cfg["hadron_ecut"]]) * u"GeV"

    for frame in sim.results
        if !(haskey(frame, inkey))
            continue
        end
        particle = frame[inkey]

        # Skip neutrinos
        if abs(Int(particle.pdg)) in [12, 14, 16]
            continue
        end

        ray = Ray(particle)
        i, t = find_intersection(ray, plane)
        if isnothing(t)
            continue
        end

        output_dir = "$(base_outdir)/event_$(lpad(frame["event_id"], 6, '0'))/shower_1/"
        if store_paths
            frame["corsika_directories"] = [output_dir]
        end
        if isdir(output_dir)
            continue
        end
        seed = Int(rand(UInt32))
        try
            corsika_run(
                particle,
                plane,
                cfg["thinning"],
                ecuts,
                cfg["corsika_path"],
                cfg["FLUPRO"],
                cfg["FLUFOR"],
                output_dir,
                seed;
                sbatch_command=sbatch_command
            )
        catch e
            event_id = frame["event_id"]
            @warn "CORSIKA failed for event $(event_id)" exception=e
        end
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
