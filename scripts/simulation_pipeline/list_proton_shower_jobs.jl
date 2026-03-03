project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using Unitful

"""
    parse_commandline()

Parse command-line arguments for the proton shower job listing script.

Arguments:
- `--injection_file`: path to the JLD2 file from the proton injection step
"""
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--injection_file"
            help = "Path to a JLD2 file containing the proton injection data"
            arg_type = String
            required = true
    end
    return parse_args(s)
end

"""
    list_proton_shower_jobs(sim, plane)

Extract event_id values from simulation results for proton CORSIKA shower jobs.
Each proton produces exactly one shower, so there is no decay_id.
Only includes events with an `injection_final_state` that intersects the
observation plane.

Returns a vector of event_id integers.
"""
function list_proton_shower_jobs(sim, plane)
    jobs = Int[]

    for frame in sim.results
        event_id = frame["event_id"]

        if !haskey(frame, "injection_final_state")
            continue
        end

        particle = frame["injection_final_state"]

        # Skip particles that don't intersect the observation plane
        ray = Tambo.Ray(particle)
        _, t = Tambo.find_intersection(ray, plane)
        if isnothing(t)
            continue
        end

        push!(jobs, event_id)
    end

    return jobs
end

"""
    main()

List all proton CORSIKA shower jobs for a proton injection file. Sets up the
observation plane from the config, calls `list_proton_shower_jobs` to enumerate
valid event_ids, and prints them as a JSON array to stdout for consumption by
the Snakefile.
"""
function main()
    args = parse_commandline()
    injection_filename = args["injection_file"]

    # Load simulation from JLD2
    sim = jldopen(injection_filename) do file
        file["sim"]
    end

    # Set up the observation plane from config
    cfg = sim.config["corsika"]
    earth = Tambo.Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )
    cs = Tambo.CoordinateSystem(earth)
    d = Tambo.Direction(cfg["plane_orientation"], Tambo.ecefcoordinates)
    d = convert(cs, d)
    point = Tambo.Coordinate(cfg["plane_coordinates"] .* u"m", Tambo.ecefcoordinates)
    point = convert(cs, point)
    plane = Tambo.Plane(point, d)

    jobs = list_proton_shower_jobs(sim, plane)

    # Output as JSON array of objects
    print("[")
    for (i, event_id) in enumerate(jobs)
        if i > 1
            print(",")
        end
        print("{\"event_id\":$(event_id)}")
    end
    println("]")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
