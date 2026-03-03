project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using Unitful

"""
    parse_commandline()

Parse command-line arguments for the proton event rate computation script.

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
    Φ_CR(E)

Cosmic ray proton flux (placeholder).
Simple power law: Φ = 1.8e4 * (E / 1 GeV)^{-2.7} GeV^{-1} m^{-2} s^{-1} sr^{-1}

This is a rough all-particle flux approximation. Replace with a more accurate
parameterization (e.g., Global Spline Fit) for production results.
"""
function Φ_CR(E)
    γ = 2.7
    E0 = 1.0u"GeV"
    norm = 1.8e4 * u"GeV^-1 * m^-2 * s^-1 * sr^-1"
    return norm * (E / E0)^(-γ)
end

"""
    compute_proton_event_rate(frames, nevent)

Compute the expected triggered proton event rate per year.

For each triggered frame, the event weight is:
    w_i = 1 / p_mc_surface(wp_i) / N_generated

The rate is:
    rate = Σ_i Φ_CR(E_i) * w_i * (1 year)
"""
function compute_proton_event_rate(frames, nevent)
    rate = 0.0
    n_valid = 0
    for frame in frames
        wp = frame["weight_params"]
        mc = Tambo.p_mc_surface(wp)

        if ustrip(mc) == 0.0
            continue
        end

        E = frame["injection_initial_state"].energy
        w = Φ_CR(E) / mc / nevent * u"yr"
        rate += ustrip(u"s/s", w)
        n_valid += 1
    end
    return rate, n_valid
end

"""
    main()

Compute and print the expected triggered proton event rate per year. Loads the triggered
JLD2 file, calls `compute_proton_event_rate` to sum oneweight contributions weighted by
a cosmic ray proton flux, and prints the result.
"""
function main()
    args = parse_commandline()
    input_filename = args["input"]
    nevent = args["nevent"]

    sim = jldopen(input_filename) do file
        file["sim"]
    end

    n_triggered = length(sim.results)
    println("Triggered events: $n_triggered")
    println("N_generated: $(Int(nevent))")
    println()

    rate, n_valid = compute_proton_event_rate(sim.results, nevent)

    n_target = 5000
    n_simulated = length(sim.config["detector_bvh"].triangles)
    scaling = n_target / n_simulated
    scaled_rate = rate * scaling

    println("Events with valid weights: $n_valid / $n_triggered")
    println("Simulated detectors: $n_simulated  →  scaled to $n_target (×$(round(scaling, digits=3)))")
    println("Expected triggered proton events per year (scaled): $scaled_rate")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
