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
        "--input"
            help = "Path to triggered JLD2 file"
            arg_type = String
            required = true
        "--nevent"
            help = "Number of events generated in MC (for normalization)"
            arg_type = Float64
            required = true
        "--nmodules"
            help = "Minimum number of modules hit required to include a frame"
            arg_type = Int
            default = 0
    end
    return parse_args(s)
end

"""
    Φ_nu(E)

IceCube astrophysical neutrino flux (per flavor).
Φ = 1.8e-18 * (E / 100 TeV)^{-2.52} GeV^{-1} cm^{-2} s^{-1} sr^{-1}
"""
function Φ_nu(E)
    γ = 2.52
    E0 = 100e3 * u"GeV"  # 100 TeV
    norm = 1.8e-18 * u"GeV^-1 * cm^-2 * s^-1 * sr^-1"
    return norm * (E / E0)^(-γ)
end

"""
    Φ_cr(E)

Cosmic ray proton flux (all-particle approximation).
Φ = 1.8e4 * (E / 1 GeV)^{-2.7} GeV^{-1} m^{-2} s^{-1} sr^{-1}
"""
function Φ_cr(E)
    γ = 2.7
    E0 = 1.0 * u"GeV"
    norm = 1.8e4 * u"GeV^-1 * m^-2 * s^-1 * sr^-1"
    return norm * (E / E0)^(-γ)
end

function compute_neutrino_event_rate(frames, nevent)
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
        w = phys / mc / nevent * Φ_nu(E) * u"yr"
        rate += ustrip(u"s/s", w)
        n_valid += 1
    end
    return rate, n_valid
end

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
        w = Φ_cr(E) / mc / nevent * u"s"
        rate += ustrip(u"s/s", w)
        n_valid += 1
    end
    return rate, n_valid
end

function main()
    args = parse_commandline()
    input_filename = args["input"]
    nevent = args["nevent"]

    sim = jldopen(input_filename) do file
        file["sim"]
    end

    pdg = sim.config["injection"]["pdg"]
    is_neutrino = (pdg == 16)
    particle_label = is_neutrino ? "tau neutrino (PDG 16)" : "proton (PDG 2212)"

    nmodules = args["nmodules"]
    n_triggered = length(sim.results)
    println("Particle type: $particle_label")
    println("Triggered events: $n_triggered")
    println("N_generated: $(Int(nevent))")
    println()

    if nmodules > 0
        frames = filter(sim.results) do f
            haskey(f, "corsika_hits") &&
            length(unique(getproperty.(f["corsika_hits"], :module_index))) >= nmodules
        end
        println("Frames with ≥$nmodules modules hit: $(length(frames)) / $n_triggered")
    else
        frames = sim.results
    end

    if is_neutrino
        rate, n_valid = compute_neutrino_event_rate(frames, nevent)
    else
        rate, n_valid = compute_proton_event_rate(frames, nevent)
    end

    n_target = 5000
    n_simulated = length(sim.config["detector_bvh"].triangles)
    scaling = n_target / n_simulated
    scaled_rate = rate * scaling

    rate_label = is_neutrino ? "per year" : "Hz"
    println("Events with valid weights: $n_valid / $n_triggered")
    println("Simulated detectors: $n_simulated  →  scaled to $n_target (×$(round(scaling, digits=3)))")
    println("Expected triggered event rate (scaled): $scaled_rate $rate_label")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
