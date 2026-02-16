project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using Unitful

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--injection_file"
            help = "Path to a JLD2 file containing the simulation data"
            arg_type = String
            required = true
    end
    return parse_args(s)
end

"""
    list_shower_jobs(sim, plane)

Extract event_id/decay_id pairs from simulation results for CORSIKA shower jobs.
Excludes neutrinos (PDG codes 12, 14, 16) since they don't produce showers.
Also excludes particles that don't intersect the observation plane.
Returns a vector of (event_id, decay_id) tuples.
"""
function list_shower_jobs(sim, plane)
    jobs = Tuple{Int, Int}[]

    for frame in sim.results
        event_id = frame["event_id"]

        if !haskey(frame, "proposal_decay_products")
            continue
        end

        decay_products = frame["proposal_decay_products"]

        for (decay_id, particle) in enumerate(decay_products)
            # Skip neutrinos - they don't produce showers
            if abs(Int(particle.pdg)) in [12, 14, 16]
                continue
            end
            # Skip particles that don't intersect the observation plane
            ray = Tambo.Ray(particle)
            _, t = Tambo.find_intersection(ray, plane)
            if isnothing(t)
                continue
            end
            push!(jobs, (event_id, decay_id))
        end
    end

    return jobs
end

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

    jobs = list_shower_jobs(sim, plane)

    # Output as JSON array of objects (manual formatting to avoid JSON dependency)
    print("[")
    for (i, job) in enumerate(jobs)
        if i > 1
            print(",")
        end
        print("{\"event_id\":$(job[1]),\"decay_id\":$(job[2])}")
    end
    println("]")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
