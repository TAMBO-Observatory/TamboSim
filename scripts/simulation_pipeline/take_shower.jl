project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using StaticArrays
using Unitful

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--config"
            help = "Path to a TOML config file"
            arg_type = String
            required = true
        "--injection_file"
            help = "Path to a JLD2 file containing the simulation data"
            arg_type = String
            required = true
        "--shower_dir"
            help = "Path to directory in which to save the output"
            arg_type = String
            required = true
        "--event_id"
            help = "Event ID in the simulation results"
            arg_type = Int
            required = true
        "--decay_id"
            help = "ID of the decay particle from the tau to simulate"
            arg_type = Int
            required = true
        "--simset_id"
            help = "Simulation set ID"
            arg_type = Int
            required = true
    end
    return parse_args(s)
end

function main()
    args = parse_commandline()
    injection_filename = args["injection_file"]
    shower_dir = args["shower_dir"]
    event_id = args["event_id"]
    decay_id = args["decay_id"]
    simset_id = args["simset_id"]

    # Load simulation from JLD2
    sim = jldopen(injection_filename) do file
        file["sim"]
    end

    # Find event by event_id
    frame = nothing
    for f in sim.results
        if f["event_id"] == event_id
            frame = f
            break
        end
    end

    if isnothing(frame)
        error("Event ID $event_id not found in simulation results")
    end

    if !haskey(frame, "proposal_decay_products")
        error("Event ID $event_id has no proposal_decay_products")
    end

    decay_products = frame["proposal_decay_products"]
    if decay_id < 1 || decay_id > length(decay_products)
        error("Decay ID $decay_id is out of range (1-$(length(decay_products)))")
    end

    particle = decay_products[decay_id]

    # Skip neutrinos
    if abs(Int(particle.pdg)) in [12, 14, 16]
        println("Skipping neutrino")
        return
    end

    # Setup plane and energy cuts from config
    cfg = sim.config["corsika"]
    earth = Tambo.Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )

    d = Tambo.Direction(cfg["plane_orientation"], Tambo.ecefcoordinates)
    d = convert(Tambo.CoordinateSystem(earth), d)
    point = Tambo.Coordinate(cfg["plane_coordinates"] .* u"m", Tambo.ecefcoordinates)
    point = convert(Tambo.CoordinateSystem(earth), point)
    plane = Tambo.Plane(point, d)

    ecuts = SVector{4, Float64}([cfg["em_ecut"], cfg["photon_ecut"],
                                  cfg["mu_ecut"], cfg["hadron_ecut"]]) * u"GeV"

    # Generate reproducible seed based on simset_id, event_id, and decay_id
    base_pinecone = get(cfg, "pinecone", 925)
    seed = abs(hash(base_pinecone + simset_id * 1000000 + event_id * 1000 + decay_id)) % typemax(Int32)

    # Create output directory
    output_dir = "$(shower_dir)/event_$(lpad(event_id, 6, '0'))/shower_$(decay_id)/"
    if !isdir(output_dir)
        mkpath(output_dir)
    end

    Tambo.corsika_run(
        particle,
        plane,
        cfg["thinning"],
        ecuts,
        cfg["corsika_path"],
        cfg["FLUPRO"],
        cfg["FLUFOR"],
        output_dir,
        Int64(seed)
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
