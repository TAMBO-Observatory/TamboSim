project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using Unitful

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
    main()

Compute and print the expected triggered event rate per year. Loads the triggered
JLD2 file, calls `compute_event_rate` to sum oneweight contributions weighted by
the IceCube astrophysical flux, and prints the result.
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

    rate, n_valid = compute_event_rate(sim.results, nevent)

    n_target = 5000
    n_simulated = length(sim.config["detector_bvh"].triangles)
    scaling = n_target / n_simulated
    scaled_rate = rate * scaling

    println("Events with valid weights: $n_valid / $n_triggered")
    println("Simulated detectors: $n_simulated  →  scaled to $n_target (×$(round(scaling, digits=3)))")
    println("Expected triggered events per year (scaled): $scaled_rate")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
