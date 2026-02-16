project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using LinearAlgebra
using ProgressMeter
using Rotations
using Unitful

"""
    parse_commandline()

Parse command-line arguments for the CORSIKA hit processing script.

Arguments:
- `--injection_file`: path to the JLD2 file from the injection step
- `--shower_dir`: directory containing CORSIKA shower output subdirectories
- `--output`: output JLD2 file (defaults to overwriting `injection_file`)
"""
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--injection_file"
            help = "Path to a JLD2 file containing the simulation data"
            arg_type = String
            required = true
        "--shower_dir"
            help = "Path to directory containing CORSIKA shower outputs"
            arg_type = String
            required = true
        "--output"
            help = "Output JLD2 file (if not specified, overwrites injection_file)"
            arg_type = String
            default = nothing
    end
    return parse_args(s)
end

"""
    intersect_module(event, bvh)

Find the detection unit hit by a CORSIKA particle. Traces a ray from the particle
in both forward and reverse directions against the detection unit BVH. Returns the
first `TriangleIntersection` found, or `nothing` if the particle misses all modules.
"""
function intersect_module(event, bvh)
    ray = Tambo.Ray(event.particle)
    ixs = Tambo.intersect_all(bvh, reverse(ray))
    length(ixs) == 0 || return last(ixs)
    ixs = Tambo.intersect_all(bvh, ray)
    length(ixs) == 0 || return first(ixs)
    return nothing
end

"""
    build_detection_units(earth, sim)

Construct the detector array as a BVH of oriented bounding boxes (OBBs). Places
detection units on a hexagonal grid (125 m spacing) over the topography surface.
Each unit is a 2m × 2m × 0.25m OBB oriented to the local surface normal.
Returns `(bvh, coordinate_system)`.
"""
function build_detection_units(earth, sim)
    cs = Tambo.CoordinateSystem(earth)
    bvh = Tambo.BVHTree(earth.topography[earth.detector_region])
    up = Tambo.Direction([0.0, 0.0, 1.0], cs)

    # Get plane parameters from config
    point = Tambo.Coordinate(sim.config["corsika"]["plane_coordinates"] .* u"m", Tambo.ecefcoordinates)
    point = convert(cs, point)
    direction = Tambo.Direction(sim.config["corsika"]["plane_orientation"], Tambo.ecefcoordinates)
    direction = convert(cs, direction)
    plane = Tambo.Plane(point, direction)

    # Calculate grid spacing
    Δy = 125.0u"m"
    Δx = dot(up, plane.normal) * Δy * sqrt(3) / 2

    # Build grid of detection unit positions
    ps = Tambo.Coordinate[]
    base_xs = collect(-1000u"m":Δx:750u"m")
    base_ys = collect(-2000u"m":Δy:2000u"m")

    for (idx, y) in enumerate(base_ys)
        xoffset = mod(idx, 2) == 0 ? 0.0u"m" : Δx / 2
        xs = base_xs .+ xoffset
        coords = [Tambo.Coordinate(x, y, 0.0u"m", cs) for x in xs]
        rays = Tambo.Ray.(coords, Ref(up))
        for ray in rays
            ixs = Tambo.intersect_all(bvh, ray)
            if length(ixs) == 0
                continue
            end
            push!(ps, ray.origin)
        end
    end

    # Create oriented bounding boxes for detection units
    detection_units = Tambo.OBB{Float64}[]
    half_lengths = [1.0u"m", 1.0u"m", 0.125u"m"]
    for p in ps
        ray = Tambo.Ray(p, up)
        ixs = Tambo.intersect_all(bvh, ray)
        n̂ = cross(ixs[1].normal, up)
        ψ = acos(dot(ixs[1].normal, up))
        rot = AngleAxis(ψ, n̂...)
        center = ixs[1].point
        obb = Tambo.OBB(center, rot, half_lengths)
        push!(detection_units, obb)
    end

    return Tambo.BVHTree(detection_units), cs
end

"""
    main()

Process CORSIKA shower output into detector hits. Builds the detection unit array,
reads CORSIKA particle data for each event, ray-traces particles against the detector
BVH, and stores the resulting hits as `corsika_hits` in each frame. Saves the updated
`Simulation` to a JLD2 file.
"""
function main()
    args = parse_commandline()
    injection_filename = args["injection_file"]
    shower_dir = args["shower_dir"]
    output_filename = isnothing(args["output"]) ? injection_filename : args["output"]

    # Load simulation from JLD2
    sim = jldopen(injection_filename) do file
        file["sim"]
    end

    # Setup geometry
    earth = Tambo.Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )
    detection_unit_bvh, cs = build_detection_units(earth, sim)

    # Process each frame
    @showprogress "Processing CORSIKA hits" for frame in sim.results
        event_id = frame["event_id"]
        event_dir = "$(shower_dir)/event_$(lpad(event_id, 6, '0'))/"

        hits = Tambo.TriangleIntersection[]

        # Check if event directory exists
        if !isdir(event_dir)
            continue
        end

        # read_corsika expects event_dir containing shower_*/particles/ subdirectories
        events = nothing
        try
            events = Tambo.read_corsika(event_dir, cs)
        catch e
            # No CORSIKA data for this event, skip
            continue
        end

        # Find intersections with detection units
        for event in events
            ix = intersect_module(event, detection_unit_bvh)
            isnothing(ix) && continue
            push!(hits, ix)
        end

        frame["corsika_hits"] = hits
    end

    # Create output directory if needed
    output_dir = dirname(output_filename)
    if output_dir != "" && !isdir(output_dir)
        mkpath(output_dir)
    end

    # Save updated simulation
    jldopen(output_filename, "w") do file
        file["sim"] = sim
    end

    println("Saved to: $output_filename")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
