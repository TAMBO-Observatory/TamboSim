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
    list_proton_shower_jobs(sim, detector_bvh)

Extract event_id values from simulation results for proton CORSIKA shower jobs.
Each proton produces exactly one shower, so there is no decay_id.
Only includes events with an `injection_final_state` that intersects the
detector region BVH.

Returns a vector of event_id integers.
"""
function list_proton_shower_jobs(sim, detector_bvh)
    jobs = Int[]

    for frame in sim.results
        event_id = frame["event_id"]

        if !haskey(frame, "injection_final_state")
            continue
        end

        particle = frame["injection_final_state"]

        # Skip particles that don't intersect the detector region
        ray = Tambo.Ray(particle)
        isect = Tambo.find_intersect(ray, detector_bvh)
        if isnothing(isect)
            continue
        end

        push!(jobs, event_id)
    end

    return jobs
end

"""
    main()

List all proton CORSIKA shower jobs for a proton injection file. Builds a BVH from
the detector region, calls `list_proton_shower_jobs` to enumerate valid event_ids,
and prints them as a JSON array to stdout for consumption by the Snakefile.
"""
function main()
    args = parse_commandline()
    injection_filename = args["injection_file"]

    # Load simulation from JLD2
    sim = jldopen(injection_filename) do file
        file["sim"]
    end

    # Build detector region BVH for intersection filtering
    earth = Tambo.Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )
    detector_bvh = Tambo.BVHTree(earth.topography[earth.detector_region])

    jobs = list_proton_shower_jobs(sim, detector_bvh)

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
