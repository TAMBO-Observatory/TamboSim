project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using Unitful

"""
    parse_commandline()

Parse command-line arguments for the shower job listing script.

Arguments:
- `--injection_file`: path to the JLD2 file from the injection step
"""
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
    list_shower_jobs(sim, detector_bvh)

Extract event_id/decay_id pairs from simulation results for CORSIKA shower jobs.
Excludes neutrinos (PDG codes 12, 14, 16) since they don't produce showers.
Also excludes particles that don't intersect the detector region BVH.
Returns a vector of (event_id, decay_id) tuples.
"""
function list_shower_jobs(sim, detector_bvh)
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
            # Skip particles that don't intersect the detector region
            ray = Tambo.Ray(particle)
            isect = Tambo.find_intersect(ray, detector_bvh)
            if isnothing(isect)
                continue
            end
            push!(jobs, (event_id, decay_id))
        end
    end

    return jobs
end

"""
    main()

List all CORSIKA shower jobs for an injection file. Builds a BVH from the detector
region, calls `list_shower_jobs` to enumerate valid `(event_id, decay_id)` pairs,
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

    jobs = list_shower_jobs(sim, detector_bvh)

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
