include("testsetup.jl")
"""
Injection regression tests for TamboSim.

These tests run full injection events through the Earth model and verify that
key statistical properties remain consistent across code changes:
- Mean energy of injected events for different spectral indices
- Fraction of events with successful injection
- Fraction of events where the injection final state is in air

Uses fixed random seeds for deterministic reproducibility.
Requires HDF5 geometry and cross-section data files.
"""

import TamboSim: UnitfulPowerLawSampler, UniformAngularSampler, CoordinateSystem,
              precompute_detector_properties, inject_neutrino_event, CrossSection,
              init_proposal, proposal_propagate, is_proposal_available

"""
    isinair(particle, prem, bvh)

Returns true if the particle is above the Earth's topography (in air).
"""
function isinair(particle, prem, bvh)
    d = Direction(
        normalize(convert(ecefcoordinates, particle.position)),
        ecefcoordinates
    )
    d = convert(particle.position.coordinate_system, d)
    ray = Ray(particle.position, d)
    return length(intersect_all(prem, bvh, ray)) == 0
end

function run_injection(prem, bvh, cs, detector_region, xs, detector_props, as, gamma, n_events, seed)
    pl = UnitfulPowerLawSampler(gamma, 3e5u"GeV", 1e9u"GeV")
    Random.seed!(seed)

    initial_energies = Float64[]
    n_successful = 0
    n_in_air = 0

    for i in 1:n_events
        tr_seed = rand(UInt32)
        istate, cstate, fstate, wp = inject_neutrino_event(16, prem, bvh, cs, detector_region, as, pl, xs, detector_props; tr_seed=tr_seed)
        e_val = ustrip(u"GeV", istate.energy)
        if !isnan(e_val)
            push!(initial_energies, e_val)
        end
        if !isnan(fstate.energy)
            n_successful += 1
            if isinair(fstate, prem, bvh)
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
    geometry_path = get_tambosim_path() * "/resources/geometry/colca_valley_3000.jld2"
    xs_path = get_tambosim_path() * "/resources/cross_section_tables/cross_sections.h5:CSMS_nutau"

    frames_geo = load_frames(geometry_path)
    g_frame = TamboSim._get_last_frame(frames_geo, 'G')
    d_frame = TamboSim._get_last_frame(frames_geo, 'D')
    prem            = g_frame["prem"]
    bvh             = g_frame["bvh"]
    cs              = g_frame["cs"]
    topography      = g_frame["topography"]
    detector_region = d_frame["detector_region"]

    xs = CrossSection(xs_path)
    detector_props = precompute_detector_properties(topography, detector_region)
    as = UniformAngularSampler(deg2rad(0.0), deg2rad(117.0), deg2rad(90.0), deg2rad(290.0))

    # PROPOSAL must be initialized before injection (the through-Earth step uses it
    # for charged-lepton transport).
    tables_path = get_tambosim_path() * "/resources/proposal_tables"
    init_proposal(Dict("tablespath" => tables_path, "vcut" => 0.5))

    # ---- Single seeded event: injection + propagation ----
    @testset "Single seeded injection + propagation" begin
        pl = UnitfulPowerLawSampler(1.0, 3e5u"GeV", 1e9u"GeV")

        # Fixed seeds for TauRunner (tr_seed) and Julia RNG
        Random.seed!(3)
        tr_seed = UInt32(3723491101)

        istate, cstate, fstate, wp = inject_neutrino_event(
            16, prem, bvh, cs, detector_region, as, pl, xs, detector_props; tr_seed=tr_seed
        )

        # Injection must succeed
        @test !isnan(fstate.energy)
        @test ustrip(u"GeV", fstate.energy) > 0.0

        # Energy must decrease through Earth (interaction losses)
        @test fstate.energy <= istate.energy

        # Propagate with fixed PROPOSAL seed (PROPOSAL already initialized above)
        proposal_seed = Int32(12345)
        losses, cont_e, secs, prop_final = proposal_propagate(fstate, prem, bvh, proposal_seed)

        # Final state must have lower energy than injection final state
        @test prop_final.energy <= fstate.energy
        @test ustrip(u"GeV", prop_final.energy) > 0.0

        # Must have stochastic losses
        @test length(losses) > 0

        # Must have decay products
        @test length(secs) > 0

        # Decay products: positive energy, unit directions, energy conservation
        for dp in secs
            @test ustrip(u"GeV", dp.energy) > 0.0
            @test isapprox(norm(dp.direction.point), 1.0, atol=1e-6)
        end
        total_decay_e = sum(ustrip(u"GeV", dp.energy) for dp in secs)
        @test total_decay_e <= ustrip(u"GeV", fstate.energy)

        # Reproducibility: same seeds must give identical results
        Random.seed!(3)
        istate2, cstate2, fstate2, wp2 = inject_neutrino_event(
            16, prem, bvh, cs, detector_region, as, pl, xs, detector_props; tr_seed=tr_seed
        )
        @test istate2.energy == istate.energy
        @test fstate2.energy == fstate.energy

        losses2, cont_e2, secs2, prop_final2 = proposal_propagate(fstate2, prem, bvh, proposal_seed)
        @test prop_final2.energy == prop_final.energy
        @test length(secs2) == length(secs)
        for (a, b) in zip(secs, secs2)
            @test a.energy == b.energy
            @test a.pdg == b.pdg
        end
    end

    n_events = 10000
    seed = 925

    # Run both gammas once, reuse results across testsets
    r1 = run_injection(prem, bvh, cs, detector_region, xs, detector_props, as, 1.0, n_events, seed)
    r2 = run_injection(prem, bvh, cs, detector_region, xs, detector_props, as, 2.0, n_events, seed)

    # ---- Gamma = 1.0 (flat spectrum) ----
    @testset "Injection gamma=1.0" begin
        @test isapprox(r1.mean_log_e, 7.228, atol=0.02)
        @test isapprox(r1.frac_successful, 0.418, atol=0.02)
        # Decimated mesh has gaps so more taus exit in air than with the full mesh
        @test isapprox(r1.frac_in_air, 0.086, atol=0.01)
    end

    # ---- Gamma = 2.0 (steeper spectrum) ----
    @testset "Injection gamma=2.0" begin
        @test isapprox(r2.mean_log_e, 5.910, atol=0.02)
        @test isapprox(r2.frac_successful, 0.419, atol=0.02)
        @test isapprox(r2.frac_in_air, 0.058, atol=0.01)
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

    # Phase 1: collect injection final states
    n_prop_events = 1000
    prop_seed = 925

    fstates_g1 = Particle{Float64}[]
    fstates_g2 = Particle{Float64}[]

    for (gamma, fstates) in [(1.0, fstates_g1), (2.0, fstates_g2)]
        pl = UnitfulPowerLawSampler(gamma, 3e5u"GeV", 1e9u"GeV")
        Random.seed!(prop_seed)
        for i in 1:n_prop_events
            tr_seed = rand(UInt32)
            istate, cstate, fstate, wp = inject_neutrino_event(16, prem, bvh, cs, detector_region, as, pl, xs, detector_props; tr_seed=tr_seed)
            if !isnan(fstate.energy)
                push!(fstates, fstate)
            end
        end
    end

    # Phase 2: initialize PROPOSAL and propagate
    tables_path = get_tambosim_path() * "/resources/proposal_tables"
    init_proposal(Dict("tablespath" => tables_path, "vcut" => 0.5))

    @testset "Post-propagation in-air fraction" begin
        for (gamma, fstates, expected_frac) in [
            (1.0, fstates_g1, 0.200),
            (2.0, fstates_g2, 0.197)
        ]
            n_prop_air = 0
            for (j, fs) in enumerate(fstates)
                losses, cont_e, secs, prop_final = proposal_propagate(fs, prem, bvh, j)
                if isinair(prop_final, prem, bvh)
                    n_prop_air += 1
                end
            end
            frac_prop_air = n_prop_air / length(fstates)
            @test isapprox(frac_prop_air, expected_frac, atol=0.02)
        end
    end

    @testset "Decay products populated" begin
        # Propagate tau leptons and verify that decay products are
        # non-empty, physically consistent, and energy-conserving.
        n_with_decay = 0
        n_tested = 0

        for (j, fs) in enumerate(fstates_g1)
            losses, cont_e, secs, prop_final = proposal_propagate(fs, prem, bvh, j)
            n_tested += 1

            if !isempty(secs)
                n_with_decay += 1

                # Each decay product must have positive energy
                for dp in secs
                    @test ustrip(u"GeV", dp.energy) > 0.0
                end

                # Decay product energies should not exceed the parent energy
                total_decay_e = sum(ustrip(u"GeV", dp.energy) for dp in secs)
                parent_e = ustrip(u"GeV", fs.energy)
                @test total_decay_e <= parent_e

                # Direction vectors should be unit-normalized
                for dp in secs
                    d = dp.direction.point
                    @test isapprox(norm(d), 1.0, atol=1e-6)
                end
            end
        end

        # The vast majority of tau propagations should end in decay
        frac_decayed = n_with_decay / n_tested
        @test frac_decayed > 0.9
    end
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Injection Regression" begin
        run_injection_regression_tests()
    end
end
