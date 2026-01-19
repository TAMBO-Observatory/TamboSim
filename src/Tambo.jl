module Tambo

export Ray,
       Coordinate,
       Direction,
       Earth,
       intersect_all,
       inject!,
       proposal_propagation!,
       cut_frames!,
       Simulation,
       ecefcoordinates


using Arrow
using CoordinateTransformations
using Dierckx: Spline1D, Spline2D
using Distributions: Uniform, Poisson
using Glob
using HDF5
using Integrals
using JLD2: jldopen, JLDFile, load
using LibGit2
using LinearAlgebra
using Parquet2
using ProgressMeter
using PyCall: PyCall, PyNULL, PyObject
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
include("python_interfaces/python_interfaces.jl")
include("corsika/corsika.jl")
include("frames/frames.jl")

"""
    __init__()

Initializes the Tambo module.

This function is automatically called when the module is loaded. It retrieves and prints
the Git commit hash of the Tambo repository and displays a welcome message with ASCII art.
"""
function __init__()
    
    tr_init()
    commit_hash = get_git_commit_hash()
    if isinteractive()
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
    git_repo_path = ENV["TAMBOSIM_PATH"]

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
    if "TAMBOSIM_PATH" ∉ keys(ENV)
        return
    end
    for (k, v) in pairs(d)
        if isa(v, String)
            d[k] = replace(v, "_TAMBOSIM_PATH_" => ENV["TAMBOSIM_PATH"])
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
    cross_section = CrossSection(cfg["xs_location"])
    detector_bvh = BVHTree(earth.topography[earth.detector_region])
    detector_areas = area.(earth.topography[earth.detector_region])
    detector_normals = normal.(earth.topography[earth.detector_region])
    Random.seed!(cfg["pinecone"])

    @showprogress for frame in sim.results
        tr_seed = rand(UInt32)
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


    @showprogress for frame in sim.results
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
        end
        if store_paths
            frame["corsika_directories"] = paths
        end
    end
end

# Custom display methods for Tambo types (must be at end after all types are defined)
include("display.jl")

end # module
