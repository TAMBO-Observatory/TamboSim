project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using StaticArrays
using Unitful

"""
    parse_commandline()

Parse command-line arguments for the CORSIKA shower script.

Arguments:
- `--config`: path to a TOML configuration file
- `--injection_file`: path to the JLD2 file from the injection step
- `--shower_dir`: directory in which to write CORSIKA output
- `--event_id`: event index in the simulation results
- `--simset_id`: simulation set ID (used in seed generation)
"""
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
        "--simset_id"
            help = "Simulation set ID"
            arg_type = Int
            required = true
    end
    return parse_args(s)
end

"""
    main()

Run a single CORSIKA air shower for the tau at the air entry point of one event.
Loads the injection JLD2, locates the event by `event_id`, reads the
`proposal_air_entry_state` particle, and calls `Tambo.corsika_run`. The random
seed is derived from `simset_id` and `event_id` to ensure reproducibility.
"""
function main()
    args = parse_commandline()
    injection_filename = args["injection_file"]
    shower_dir = args["shower_dir"]
    event_id = args["event_id"]
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

    if !haskey(frame, "proposal_air_entry_state")
        error("Event ID $event_id has no proposal_air_entry_state")
    end

    particle = frame["proposal_air_entry_state"]

    # Skip neutrinos
    if abs(Int(particle.pdg)) in [12, 14, 16]
        println("Skipping neutrino")
        return
    end

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

    # Generate reproducible seed based on simset_id and event_id
    base_pinecone = get(cfg, "pinecone", 925)
    seed = abs(hash(base_pinecone + simset_id * 1000000 + event_id)) % typemax(Int32)

    # Create output directory
    output_dir = "$(shower_dir)/event_$(lpad(event_id, 6, '0'))/shower_1/"
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
