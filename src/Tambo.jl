module Tambo

using Arrow
using CoordinateTransformations
using Dierckx: Spline1D, Spline2D
using Distributions: Uniform, Poisson
using Integrals
using HDF5
using JLD2: jldopen, JLDFile, load
using LibGit2
using LinearAlgebra
using ProgressBars
using PyCall: PyCall, PyNULL, PyObject
using Random
using Rotations
using StaticArrays
using StatsBase
using TOML
using Unitful

include("units.jl")
include("geometry/geometry.jl")
include("ray_tracing/ray_tracing.jl")
include("samplers/samplers.jl")
include("particles/particles.jl")
include("injection/injection.jl")
include("python_interfaces/python_interfaces.jl")

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


@Base.kwdef mutable struct Simulation
    config::Dict{String, Any}
    results::Dict{String, Any}
    function Simulation(config, results)
        @assert "geometry" in keys(config) "Geometry information must be provided"
        @assert "steering" in keys(config) "Steering information must be provided"
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

    expected_top_level_keys = Set(["geometry", "steering", "injection", "proposal", "corsika"])
    unexpected_keys = setdiff(Set(keys(config)), expected_top_level_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in config file: ", unexpected_keys)
    end

    expected_steering_keys = Set(["nevent", "pinecone", "run_number"])
    unexpected_keys = setdiff(Set(keys(config["steering"])), expected_steering_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in steering section of config file: ", unexpected_keys)
    end

    expected_geo_keys = Set(["geo_spline_path", "tambo_coordinates", "plane_orientation"])
    unexpected_keys = setdiff(Set(keys(config["geometry"])), expected_geo_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in geometry section of config file: ", unexpected_keys)
    end

    expected_injection_keys = Set(["nu_pdg", "gamma", "gamma", "emin", "emax", "thetamin", "thetamax", "phimin", "phimax", "r_injection", "l_endcap", "xs_dir", "xs_model", "interaction", "track_progress", "length", "width"])
    unexpected_keys = setdiff(Set(keys(config["injection"])), expected_injection_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in injection section of config file: ", unexpected_keys)
    end

    expected_proposal_keys = Set(["ecut", "vcut", "do_interpolate", "do_continuous", "tablespath", "track_progress"])
    unexpected_keys = setdiff(Set(keys(config["proposal"])), expected_proposal_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in proposal section of config file: ", unexpected_keys)
    end

    expected_corsika_keys = Set(["should_run_corsika", "parallelize_corsika", "thinning", "hadron_ecut", "em_ecut", "photon_ecut", "mu_ecut", "corsika_path", "track_progress", "FLUPRO", "FLUFOR"])
    unexpected_keys = setdiff(Set(keys(config["corsika"])), expected_corsika_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in corsika section of config file: ", unexpected_keys)
    end
end

#function Simulation(config_file::String, injection_file::String="")
#    config = TOML.parsefile(config_file)
#    validate_config_file(config)
#    relativize!(config)
#    if injection_file == ""
#        results = Dict{String, Any}()
#
#    else
#        results = load(injection_file)
#    end
#    return Simulation(config, results)
#end
#
#function inject_ν!(
#    sim::Simulation,
#    config::Dict{String, Any},
#    simset_id::Int64,
#    seed::Int64;
#    outkey="injected_events",
#    track_progress=false
#)
#    relativize!(config)
#    sim.config[outkey] = config
#
#    geo = Geometry(sim.config["geometry"])
#    injector = Injector(config, geo)
#    events = Vector{InjectionEvent}(undef, sim.config["steering"]["nevent"])
#    itr = 1:sim.config["steering"]["nevent"]
#    if track_progress
#        println("Injecting neutrinos")
#        itr = ProgressBar(itr)
#    end
#
#    event_id_offset = simset_id * sim.config["steering"]["nevent"]
#    for idx in itr
#        tr_seed = seed + idx
#        event_id = event_id_offset + idx
#        event = inject_event(injector, event_id, tr_seed)
#        events[idx] = event
#    end
#    sim.results[outkey] = events
#end
#
#function inject_ν!(
#    sim::Simulation,
#    config_file::String;
#    outkey="injected_events",
#    track_progress=false
#)
#    config = relativize!(TOML.parsefile(config_file))
#    inject_ν!(sim, config; outkey=outkey, track_progress=track_progress)
#end
#
#function inject_ν!(
#    sim::Simulation;
#    outkey="injected_events",
#    track_progress=true
#)
#    inject_ν!(
#        sim,
#        sim.config["injection"],
#        sim.config["steering"]["run_number"],
#        sim.config["steering"]["pinecone"];
#        outkey=outkey,
#        track_progress=track_progress
#    )
#end
#
#function propagate_τ!(
#    sim::Simulation,
#    config::Dict{String, Any},
#    seed::Int64;
#    inkey="injected_events",
#    outkey="proposal_events",
#    track_progress=false
#)
#    relativize!(config)
#    sim.config[outkey] = config
#
#    geo = Geometry(sim.config["geometry"])
#    events = Vector{ProposalResult}(undef, sim.config["steering"]["nevent"])
#    propagator = ProposalPropagator(config)
#    injected_events = sim.results[inkey]
#    if track_progress
#        println("Propagating taus")
#        injected_events = ProgressBar(injected_events)
#    end
#    for (idx, injected_event) in enumerate(injected_events)
#        event = propagator(
#            injected_event.event_id,
#            injected_event.final_state,
#            geo,
#            seed + idx
#        )
#        events[idx] = event
#    end
#    sim.results[outkey] = events
#end
#
#function propagate_τ!(
#    sim::Simulation,
#    config_file::String;
#    inkey::String="injected_events",
#    outkey::String="proposal_events",
#    track_progress::Bool=false
#)
#    config = relativize!(TOML.parsefile(config_file))
#    propagate_τ!(sim, config; inkey=inkey, outkey=outkey, track_progress=track_progress)
#end
#
#function propagate_τ!(
#    sim::Simulation;
#    inkey::String="injected_events",
#    outkey::String="proposal_events",
#    track_progress::Bool=true
#)
#    propagate_τ!(
#        sim,
#        sim.config["proposal"],
#        sim.config["steering"]["pinecone"];
#        inkey=inkey,
#        outkey=outkey,
#        track_progress=track_progress
#    )
#end
#
#function identify_taus_to_shower!(
#    sim::Simulation,
#    config::Dict{String, Any},
#    inkey="proposal_events",
#    outkey="corsika_indices",
#    track_progress=false
#)
#    relativize!(config)
#    proposal_events = sim.results[inkey]
#
#    #track_progress = sim.config["corsika"]["track_progress"]
#    
#    sim.config[outkey] = config
#    geo = Geometry(sim.config["geometry"])
#    # TODO wrap this into a neat little constructor
#    #plane = Plane(
#    #    geo.tambo_normal,
#    #    geo.tambo_coordinates,
#    #    geo
#    #)
#
#    indices = Vector{Tuple{Int64, Int64}}()
#
#    if track_progress
#        println("Identifying taus to shower")
#        proposal_events = ProgressBar(proposal_events)
#    end
#    for (proposal_idx, proposal_event) in enumerate(proposal_events)
#        if ~should_do_corsika(proposal_event, geo)
#        #if ~should_do_corsika(proposal_event, plane,geo)
#            continue
#        end
#        for (decay_idx,decay_event) in enumerate(proposal_event.decay_products)
#            #wanted to keep indices lined up so checking one at at ime
#            if check_neutrino(decay_event)
#                continue 
#            end
#            event_id = proposal_event.event_id
#            push!(indices, (event_id, decay_idx))
#        end
#    end
#    sim.results[outkey] = indices
#end
#
#function get_proposal_event_using_event_id(sim::Simulation, event_id::Int64)
#    proposal_events = sim.results["proposal_events"]
#    for pe in proposal_events
#        if pe.event_id == event_id
#            return pe
#        end
#    end
#    error("No proposal event found with event_id: $event_id")
#end
#
#function run_subshower!(
#    sim::Simulation,
#    config::Dict{String, Any},
#    proposal_id::Int64,
#    decay_id::Int64,
#    seed::Int64;
#    #output_path::String;
#    proposal_ids_key="corsika_indices",
#    proposal_events_key="proposal_events",
#    track_progress=false
#)
#    relativize!(config)
#
#    sim.config["corsika"] = config
#    geo = Geometry(sim.config["geometry"])
#    #plane = Plane(
#    #    geo.tambo_normal,
#    #    geo.tambo_coordinates,
#    #    geo
#    #)
#
#    println("looking for proposal event with ID $proposal_id")
#    proposal_event = get_proposal_event_using_event_id(sim, proposal_id)
#    println("got proposal event:")
#    println(proposal_event)
#    corsika_run(
#        proposal_event.decay_products[decay_id],
#        sim.config["corsika"],
#        geo,
#        proposal_id,
#        decay_id,
#        seed,
#        parallelize_corsika=false
#    )
#end
#    
#function save_simulation_to_jld2(s::Simulation, path::String)
#    @assert length(s.results["injected_events"]) == s.config["steering"]["nevent"]
#    @assert length(s.results["proposal_events"]) == s.config["steering"]["nevent"]
#    jldopen(path, "w") do file
#        file["injected_events"] = s.results["injected_events"]
#        file["proposal_events"] = s.results["proposal_events"]
#        file["corsika_indices"] = s.results["corsika_indices"]
#        file["config"] = s.config
#    end
#end
#
#function save_simulation_to_arrow(s::Simulation, path::String)
#    @assert length(s.results["injected_events"]) == s.config["steering"]["nevent"]
#    @assert length(s.results["proposal_events"]) == s.config["steering"]["nevent"]
#    if "corsika_indices" ∈ keys(s.results)
#        crska_idxs = Vector{Tuple{Int, Int}}[Tuple{Int, Int}[] for _ in 1:s.config["steering"]["nevent"]]
#        for (a, b) in s.results["corsika_indices"]
#            push!(crska_idxs[a], (a, b))
#        end
#        savestuff = (
#            proposal_events=s.results["proposal_events"],
#            injected_events=s.results["injected_events"],
#            corsika_indices=crska_idxs
#        )
#    else
#        savestuff = (
#            proposal_events=s.results["proposal_events"],
#            injected_events=s.results["injected_events"],
#        )
#    end
#
#
#    Arrow.write(path, savestuff, metadata=rec_flatten_dict(s.config))
#end

end # module
