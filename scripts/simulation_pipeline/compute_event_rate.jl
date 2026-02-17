project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using Unitful
using LinearAlgebra

"""
    parse_commandline()

Parse command-line arguments for the event rate computation script.

Arguments:
- `--input`: path to the triggered JLD2 file
- `--nevent`: total number of MC events generated (for normalization)
"""
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--input"
            help = "Path to triggered JLD2 file"
            arg_type = String
            required = true
        "--nevent"
            help = "Number of events generated in MC (for normalization)"
            arg_type = Float64
            required = true
    end
    return parse_args(s)
end

"""
    Φ(E)

IceCube astrophysical neutrino flux (per flavor).
Φ = 1.8e-18 * (E / 100 TeV)^{-2.52} GeV^{-1} cm^{-2} s^{-1} sr^{-1}
"""
function Φ(E)
    γ = 2.52
    E0 = 100e3 * u"GeV"  # 100 TeV
    norm = 1.8e-18 * u"GeV^-1 * cm^-2 * s^-1 * sr^-1"
    return norm * (E / E0)^(-γ)
end

"""
    compute_event_rate(frames, nevent)

Compute the expected triggered event rate per year.

For each triggered frame, the event weight is:
    w_i = p_phys(wp) / p_mc(wp) / N_generated

The rate is:
    rate = Σ_i Φ(E_i) * w_i * (1 year)
"""
function compute_event_rate(frames, nevent)
    rate = 0.0
    n_valid = 0
    for frame in frames
        wp = frame["weight_params"]
        mc = Tambo.p_mc(wp)
        phys = Tambo.p_phys(wp.generated_cd, wp.generated_density, wp.generated_diff_xs)

        if ustrip(mc) == 0.0 || ustrip(phys) == 0.0
            continue
        end

        E = frame["injection_initial_state"].energy
        w = phys / mc / nevent * Φ(E) * u"yr"
        rate += ustrip(u"s/s", w)
        n_valid += 1
    end
    return rate, n_valid
end

"""
    decayed_after_last_rock_air(frame, earth, plane) -> Bool

Check whether the tau in `frame` decayed after the last rock→air interface
before the observation plane. Returns `true` if the tau either:
- survived to the air interface without decaying (has `proposal_air_entry_state`), or
- decayed at a position past the last rock→air boundary.

Returns `false` if the tau decayed in rock or in an intermediate air segment
before the last rock→air boundary (i.e. it never reached the final air).
"""
function decayed_after_last_rock_air(
    frame::Tambo.Frame,
    earth::Tambo.Earth,
    plane::Tambo.Plane
)
    # New pipeline events with air_entry_state always pass
    haskey(frame, "proposal_air_entry_state") && return true

    # Need both injection and proposal final states
    haskey(frame, "injection_final_state") || return false
    haskey(frame, "proposal_final_state") || return false

    particle = frame["injection_final_state"]
    ray = Tambo.Ray(particle)
    ixs = intersect_all(earth, ray)
    densities = Tambo.compute_density(ixs, particle.direction)
    lengths = Tambo.compute_lengths(ixs)

    _, plane_t = Tambo.find_intersection(ray, plane)

    # Find cumulative distance to end of the last rock→air transition segment
    last_rock_end = nothing
    cumulative_d = 0.0u"m"
    for i in 1:length(densities)
        cumulative_d += lengths[i]
        is_rock = densities[i] > 1u"g/cm^3"
        is_next_air = (i < length(densities)) && (densities[i+1] <= 1u"g/cm^3")
        before_plane = isnothing(plane_t) || cumulative_d <= plane_t
        if is_rock && is_next_air && before_plane
            last_rock_end = cumulative_d
        end
    end

    # No rock→air boundary found — can't apply this cut meaningfully
    isnothing(last_rock_end) && return true

    # Compute how far along the ray the decay (proposal_final_state) occurred
    final_pos = convert(Tambo.ecefcoordinates, frame["proposal_final_state"].position)
    start_pos = convert(Tambo.ecefcoordinates, particle.position)
    dir = convert(Tambo.ecefcoordinates, particle.direction)
    displacement = final_pos.point .- start_pos.point  # SVector with units of m
    decay_dist = dot(displacement, dir.point)  # meters (unitful)

    return decay_dist >= last_rock_end
end

"""
    count_detector_modules(earth, plane) -> Int

Count the number of detector modules by replicating the hex grid placement
from `process_corsika_hits.jl:build_detection_units`. Modules are placed on a
125 m hexagonal grid over the detector topography region.

Takes a pre-built `Earth` and observation `Plane` to avoid redundant loading.
"""
function count_detector_modules(earth, plane)
    cs = Tambo.CoordinateSystem(earth)
    bvh = Tambo.BVHTree(earth.topography[earth.detector_region])
    up = Tambo.Direction([0.0, 0.0, 1.0], cs)

    plane_normal = convert(cs, plane.normal)

    Δy = 125.0u"m"
    Δx = dot(up, plane_normal) * Δy * sqrt(3) / 2

    n_modules = 0
    base_xs = collect(-1000u"m":Δx:750u"m")
    base_ys = collect(-2000u"m":Δy:2000u"m")

    for (idx, y) in enumerate(base_ys)
        xoffset = mod(idx, 2) == 0 ? 0.0u"m" : Δx / 2
        xs = base_xs .+ xoffset
        for x in xs
            coord = Tambo.Coordinate(x, y, 0.0u"m", cs)
            ray = Tambo.Ray(coord, up)
            ixs = Tambo.intersect_all(bvh, ray)
            if length(ixs) > 0
                n_modules += 1
            end
        end
    end
    return n_modules
end

"""
    main()

Compute and print the expected triggered event rate per year. Loads the triggered
JLD2 file, calls `compute_event_rate` to sum oneweight contributions weighted by
the IceCube astrophysical flux, and prints the result.

Scales the rate to a detector with 5000 modules based on the number of modules
in the simulated geometry.

Also computes the rate after removing events where the tau decayed before
the last rock→air interface (intermediate air segments between mountains).
"""
function main()
    args = parse_commandline()
    input_filename = args["input"]
    nevent = args["nevent"]

    sim = jldopen(input_filename) do file
        file["sim"]
    end

    earth = Tambo.Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )

    # Build observation plane once for reuse
    corsika_cfg = sim.config["corsika"]
    Tambo.relativize!(corsika_cfg)
    cs = Tambo.CoordinateSystem(earth)
    d = Tambo.Direction(corsika_cfg["plane_orientation"], Tambo.ecefcoordinates)
    d = convert(cs, d)
    point = Tambo.Coordinate(corsika_cfg["plane_coordinates"] .* u"m", Tambo.ecefcoordinates)
    point = convert(cs, point)
    plane = Tambo.Plane(point, d)

    n_triggered = length(sim.results)
    println("Triggered events: $n_triggered")
    println("N_generated: $(Int(nevent))")

    n_sim_modules = count_detector_modules(earth, plane)
    n_target_modules = 5000
    scale_factor = n_target_modules / n_sim_modules
    println("Simulated detector modules: $n_sim_modules")
    println("Target detector modules: $n_target_modules")
    println("Scale factor: $(round(scale_factor, digits=4))")
    println()

    rate, n_valid = compute_event_rate(sim.results, nevent)

    println("Events with valid weights: $n_valid / $n_triggered")
    println("Expected triggered events per year: $rate")
    println("Scaled to $n_target_modules modules: $(rate * scale_factor)")

    # Apply the last-rock→air cut
    filtered = filter(f -> decayed_after_last_rock_air(f, earth, plane), sim.results)
    n_removed = n_triggered - length(filtered)

    println()
    println("--- After removing events that decayed before last rock→air interface ---")
    println("Events removed: $n_removed")
    println("Triggered events remaining: $(length(filtered))")

    rate_filtered, n_valid_filtered = compute_event_rate(filtered, nevent)
    println("Events with valid weights: $n_valid_filtered / $(length(filtered))")
    println("Expected triggered events per year: $rate_filtered")
    println("Scaled to $n_target_modules modules: $(rate_filtered * scale_factor)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
