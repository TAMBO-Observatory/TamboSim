"""
Injection regression tests for Tambo.

These tests run full injection events through the Earth model and verify that
key statistical properties remain consistent across code changes:
- Mean energy of injected events for different spectral indices
- Fraction of events with successful injection
- Fraction of events where the injection final state is in air

Uses fixed random seeds for deterministic reproducibility.
Requires HDF5 geometry and cross-section data files.
"""

import Tambo: UnitfulPowerLawSampler, UniformAngularSampler, CoordinateSystem,
              precompute_detector_properties, inject_event, CrossSection, Earth,
              null_params, init_proposal, proposal_propagate, is_proposal_available

"""
    isinair(particle, earth)

Returns true if the particle is above the Earth's topography (in air).
Casts a ray straight up from the particle position; if it doesn't intersect
any topography, the particle is in air.
"""
function isinair(particle, earth)
    d = Direction(
        normalize(convert(ecefcoordinates, particle.position)),
        ecefcoordinates
    )
    d = convert(particle.position.coordinate_system, d)
    ray = Ray(particle.position, d)
    return length(intersect_all(earth, ray)) == 0
end

function run_injection(earth, xs, detector_props, as, gamma, n_events, seed)
    pl = UnitfulPowerLawSampler(gamma, 3e5u"GeV", 1e9u"GeV")
    Random.seed!(seed)

    initial_energies = Float64[]
    n_successful = 0
    n_in_air = 0

    for i in 1:n_events
        tr_seed = rand(UInt32)
        istate, cstate, fstate, wp = inject_event(16, earth, as, pl, xs, detector_props; tr_seed=tr_seed)
        e_val = ustrip(u"GeV", istate.energy)
        if !isnan(e_val)
            push!(initial_energies, e_val)
        end
        if !isnan(fstate.energy)
            n_successful += 1
            if isinair(fstate, earth)
                n_in_air += 1
            end
        end
    end

    mean_log_e = mean(log10.(initial_energies))
    frac_successful = n_successful / n_events
    frac_in_air = n_successful > 0 ? n_in_air / n_successful : 0.0

    return (;
        mean_log_e,
        frac_successful,
        frac_in_air,
        n_valid=length(initial_energies),
        n_successful,
        n_in_air
    )
end

function run_injection_regression_tests()
    earth_path = ENV["TAMBOSIM_PATH"] * "/resources/basic_geometry.h5:colca_valley_30000"
    xs_path = ENV["TAMBOSIM_PATH"] * "/resources/cross_section_tables/cross_sections.h5:CSMS_nutau"

    earth = Earth(earth_path, "detector1")
    xs = CrossSection(xs_path)
    detector_props = precompute_detector_properties(earth)
    as = UniformAngularSampler(deg2rad(0.0), deg2rad(117.0), deg2rad(90.0), deg2rad(290.0))

    n_events = 10000
    seed = 925

    # Run both gammas once, reuse results across testsets
    r1 = run_injection(earth, xs, detector_props, as, 1.0, n_events, seed)
    r2 = run_injection(earth, xs, detector_props, as, 2.0, n_events, seed)

    # ---- Gamma = 1.0 (flat spectrum) ----
    @testset "Injection gamma=1.0" begin
        # Mean log10(E/GeV) ~ 7.22 for gamma=1 (uniform in log-space)
        @test isapprox(r1.mean_log_e, 7.224, atol=0.01)

        # Fraction of successful injections ~ 51.6%
        @test isapprox(r1.frac_successful, 0.5164, atol=0.01)

        # Fraction of successful events with final state in air ~ 0.2%
        # Higher energy taus can travel far enough to exit the rock
        @test isapprox(r1.frac_in_air, 0.00213, atol=0.005)
    end

    # ---- Gamma = 2.0 (steeper spectrum) ----
    @testset "Injection gamma=2.0" begin
        # Mean log10(E/GeV) ~ 5.90 for gamma=2 (weighted toward lower energies)
        @test isapprox(r2.mean_log_e, 5.904, atol=0.01)

        # Fraction of successful injections ~ 52.0%
        @test isapprox(r2.frac_successful, 0.5196, atol=0.01)

        # Fraction in air ~ 0% for steeper spectrum (lower energy taus
        # don't travel far enough to exit the rock)
        @test r2.frac_in_air < 0.005
    end

    # ---- Cross-gamma consistency ----
    @testset "Cross-gamma consistency" begin
        # Steeper spectrum (gamma=2) should have lower mean energy
        @test r2.mean_log_e < r1.mean_log_e

        # Success fraction should be similar (geometry-driven, not energy-driven)
        @test isapprox(r1.frac_successful, r2.frac_successful, atol=0.05)

        # Higher energy spectrum should have more events in air
        @test r1.frac_in_air >= r2.frac_in_air
    end

    # ---- Post-propagation regression (PROPOSAL lepton propagation) ----
    # Uses fewer events (1000) since PROPOSAL propagation is compute-intensive.
    # Two-phase approach: run all injections first, then propagate, to avoid
    # conflicts between TauRunner's internal PROPOSAL usage and init_proposal.
    @testset "Post-propagation in-air fraction" begin
        n_prop_events = 1000
        prop_seed = 925

        # Phase 1: collect injection final states for both gammas
        fstates_g1 = Particle{Float64}[]
        fstates_g2 = Particle{Float64}[]

        for (gamma, fstates) in [(1.0, fstates_g1), (2.0, fstates_g2)]
            pl = UnitfulPowerLawSampler(gamma, 3e5u"GeV", 1e9u"GeV")
            Random.seed!(prop_seed)
            for i in 1:n_prop_events
                tr_seed = rand(UInt32)
                istate, cstate, fstate, wp = inject_event(16, earth, as, pl, xs, detector_props; tr_seed=tr_seed)
                if !isnan(fstate.energy)
                    push!(fstates, fstate)
                end
            end
        end

        # Phase 2: initialize PROPOSAL and propagate
        tables_path = ENV["TAMBOSIM_PATH"] * "/resources/proposal_tables"
        init_proposal(Dict("tablespath" => tables_path))

        for (gamma, fstates, expected_frac) in [
            (1.0, fstates_g1, 0.164),
            (2.0, fstates_g2, 0.155)
        ]
            n_prop_air = 0
            for (j, fs) in enumerate(fstates)
                losses, cont_e, secs, prop_final = proposal_propagate(fs, earth, j)
                if isinair(prop_final, earth)
                    n_prop_air += 1
                end
            end
            frac_prop_air = n_prop_air / length(fstates)
            @test isapprox(frac_prop_air, expected_frac, atol=0.02)
        end
    end
end
