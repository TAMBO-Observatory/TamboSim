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

function __init__()
    
    tr_init()
    commit_hash = get_git_commit_hash()
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


mutable struct Simulation
    config::Dict{String, Any}
    results::Vector{Frame}
    function Simulation(config, results)
        @assert "geometry" in keys(config) "Geometry information must be provided"
        return new(config, results)
    end
end

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

function validate_config_file(config::Dict{String, Any})
    # Check that only expected configuration parameters are present
    # so user doesn't think they're setting parameters they aren't

    #expected_top_level_keys = Set(["geometry", "steering", "injection", "proposal", "corsika"])
    #unexpected_keys = setdiff(Set(keys(config)), expected_top_level_keys)
    #if !isempty(unexpected_keys)
    #    error("Unexpected keys found in config file: ", unexpected_keys)
    #end

    #expected_steering_keys = Set(["nevent", "pinecone", "run_number"])
    #unexpected_keys = setdiff(Set(keys(config["steering"])), expected_steering_keys)
    #if !isempty(unexpected_keys)
    #    error("Unexpected keys found in steering section of config file: ", unexpected_keys)
    #end

    #expected_geo_keys = Set(["geo_spline_path", "tambo_coordinates", "plane_orientation"])
    #unexpected_keys = setdiff(Set(keys(config["geometry"])), expected_geo_keys)
    #if !isempty(unexpected_keys)
    #    error("Unexpected keys found in geometry section of config file: ", unexpected_keys)
    #end

    #expected_injection_keys = Set(["nu_pdg", "gamma", "gamma", "emin", "emax", "thetamin", "thetamax", "phimin", "phimax", "r_injection", "l_endcap", "xs_dir", "xs_model", "interaction", "track_progress", "length", "width"])
    #unexpected_keys = setdiff(Set(keys(config["injection"])), expected_injection_keys)
    #if !isempty(unexpected_keys)
    #    error("Unexpected keys found in injection section of config file: ", unexpected_keys)
    #end

    #expected_proposal_keys = Set(["ecut", "vcut", "do_interpolate", "do_continuous", "tablespath", "track_progress"])
    #unexpected_keys = setdiff(Set(keys(config["proposal"])), expected_proposal_keys)
    #if !isempty(unexpected_keys)
    #    error("Unexpected keys found in proposal section of config file: ", unexpected_keys)
    #end

    #expected_corsika_keys = Set(["should_run_corsika", "parallelize_corsika", "thinning", "hadron_ecut", "em_ecut", "photon_ecut", "mu_ecut", "corsika_path", "track_progress", "FLUPRO", "FLUFOR"])
    #unexpected_keys = setdiff(Set(keys(config["corsika"])), expected_corsika_keys)
    #if !isempty(unexpected_keys)
    #    error("Unexpected keys found in corsika section of config file: ", unexpected_keys)
    #end
end

function Simulation(config_file::String)
    config = TOML.parsefile(config_file)
    validate_config_file(config)
    relativize!(config)
    results = Frame[]
    return Simulation(config, results)
end

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
        if ~isnan(cstate.energy)
            frame["$(outprefix)_close_state"] = cstate
        end
        if ~isnan(fstate.energy)
            frame["$(outprefix)_final_state"] = fstate
        end
        frame["weight_params"] = wp
    end
end

function inject_ν!(
    sim::Simulation;
    outprefix::String="injection",
    earth::Union{Earth, Nothing}=nothing
)
    @warn("`inject_ν!` is deprecated. Please use `inject!`.")
    inject!(sim; outprefix=outprefix, earth=earth)
end

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
        if ~haskey(frame, inkey)
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

function propagate_τ!(
    sim::Simulation;
    inkey::String="injection_final_state",
    outprefix::String="proposal",
    earth::Union{Earth, Nothing}=nothing
)
    @warn("`propagate_τ!` is deprecated. Please use `proposal_propagation!`.")
    proposal_propagation!(sim; inkey=inkey, outprefix=outprefix, earth=earth)
end

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
    d = Tambo.Direction(cg["plane_orientation"], ecefcoordinates)
    d = convert(CoordinateSystem(earth), d)
    point = Coordinate(cfg["plane_coordinates"] .* u"m", ecefcoordinates)
    point = convert(CoordinateSystem(earth), point)
    plane = Plane(point, d)

    sbatch_command = parallelize ? cfg["sbatch_command"] : ""
    ecuts = SVector{4, Float64}([cfg["em_ecut"], cfg["photon_ecut"], cfg["mu_ecut"], cfg["hadron_ecut"]]) * u"GeV"
    for frame in sim.results
        if ~(haskey(frame, inkey))
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
            corsika_run(
                particle,
                plane,
                config["thinning"],
                ecuts,
                config["corsika_path"],
                config["FLUPRO"],
                config["FLUFOR"],
                output_dir,
                sim.config["steering"]["pinecone"] + frame["event_id"];
                sbatch_command=sbatch_command
            )
        end
        if store_paths
            frame["corsika_directories"] = paths
        end
    end
end

end # module
