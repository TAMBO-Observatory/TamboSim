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
            help = "Path to input JLD2 file"
            arg_type = String
            required = true
        "--nevent"
            help = "Number of events generated in MC (for normalization; defaults to value in sim config)"
            arg_type = Float64
            default = nothing
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
        w = Φ_cr(E) / mc / nevent * u"yr"
        rate += ustrip(u"s/s", w)
        n_valid += 1
    end
    return rate, n_valid
end

"""
    Phi_mu(E, cos_theta)

Atmospheric muon flux (Gaisser parameterization with Chirkin cos(theta*) modification).
Valid for E > ~100 GeV.
Returns flux in GeV^{-1} m^{-2} s^{-1} sr^{-1}.
"""
function Phi_mu(E, cos_theta)
    E_GeV = ustrip(u"GeV", E)
    cos_theta_star = sqrt((cos_theta^2 + 0.0324) / 1.0324)
    flux = 0.14e4 * E_GeV^(-2.7) * (
        1 / (1 + 1.1 * E_GeV * cos_theta_star / 115) +
        0.054 / (1 + 1.1 * E_GeV * cos_theta_star / 850)
    )
    return flux * u"GeV^-1 * m^-2 * s^-1 * sr^-1"
end

function compute_muon_event_rate(frames, nevent)
    rate = 0.0
    n_valid = 0
    for frame in frames
        wp = frame["weight_params"]
        mc = Tambo.p_mc_surface(wp)
        if ustrip(mc) == 0.0
            continue
        end
        E = frame["injection_initial_state"].energy
        dir = frame["injection_initial_state"].direction
        cos_theta = dir.point[3]  # z-component = cos(zenith)
        w = Phi_mu(E, abs(cos_theta)) / mc / nevent * u"yr"
        rate += ustrip(u"s/s", w)
        n_valid += 1
    end
    return rate, n_valid
end

function main()
    args = parse_commandline()
    input_filename = args["input"]

    sim = jldopen(input_filename) do file
        file["sim"]
    end

    nevent = isnothing(args["nevent"]) ? Float64(sim.config["injection"]["nevent"]) : args["nevent"]

    pdg = sim.config["injection"]["nu_pdg"]
    is_neutrino = abs(pdg) in (12, 14, 16)
    if is_neutrino
        particle_label = "neutrino (PDG $pdg)"
    elseif abs(pdg) == 13
        particle_label = "atmospheric muon (PDG $pdg)"
    else
        particle_label = "proton (PDG 2212)"
    end

    n_frames = length(sim.results)
    println("Particle type: $particle_label")
    println("Input events: $n_frames")
    println("N_generated: $(Int(nevent))")
    println()

    if is_neutrino
        rate, n_valid = compute_neutrino_event_rate(sim.results, nevent)
    elseif abs(pdg) == 13
        rate, n_valid = compute_muon_event_rate(sim.results, nevent)
    else
        rate, n_valid = compute_proton_event_rate(sim.results, nevent)
    end

    println("Events with valid weights: $n_valid / $n_frames")
    println("Expected events per year: $rate")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
