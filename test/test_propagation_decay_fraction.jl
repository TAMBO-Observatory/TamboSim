include("testsetup.jl")
"""
Propagation and decay-in-mountain fraction tests.

Injects neutrino events, propagates the resulting charged leptons through the
Earth with PROPOSAL, and checks what fraction reach PROPOSAL propagation and
what fraction decay inside the mountain (vs. emerging in air).

Uses fixed random seeds for deterministic reproducibility.
"""

import TamboSim: UnitfulPowerLawSampler, UniformAngularSampler, CoordinateSystem,
              precompute_detector_properties, inject_neutrino_event, CrossSection,
              init_proposal, proposal_propagate, is_proposal_available

"""
    isinair_prop(particle, prem, bvh)

Returns true if the particle is above the Earth's topography (in air).
"""
function isinair_prop(particle, prem, bvh)
    d = Direction(
        normalize(convert(ecefcoordinates, particle.position)),
        ecefcoordinates
    )
    d = convert(particle.position.coordinate_system, d)
    ray = Ray(particle.position, d)
    return length(intersect_all(prem, bvh, ray)) == 0
end

function run_propagation_decay_fraction_tests()
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

    # Phase 1: inject events and collect successful final states
    n_events = 1000
    seed = 7891
    gamma = 1.0
    pl = UnitfulPowerLawSampler(gamma, 3e5u"GeV", 1e9u"GeV")

    Random.seed!(seed)
    # taurunner_interface drives PROPOSAL's C++ propagator during Earth transit,
    # which advances PROPOSAL's own RNG. Seed it here too so this phase is
    # deterministic regardless of what earlier testsets left it in.
    TamboSim.PP.set_random_seed(Int32(seed))
    fstates = Particle{Float64}[]
    n_injected = 0
    for _ in 1:n_events
        tr_seed = rand(UInt32)
        istate, cstate, fstate, wp = inject_neutrino_event(
            16, prem, bvh, cs, detector_region, as, pl, xs, detector_props; tr_seed=tr_seed
        )
        n_injected += 1
        if !isnan(fstate.energy)
            push!(fstates, fstate)
        end
    end

    n_successful = length(fstates)

    # Phase 2: propagate with PROPOSAL
    tables_path = get_tambosim_path() * "/resources/proposal_tables"
    init_proposal(Dict("tablespath" => tables_path, "vcut" => 0.5))

    n_emerged_air = 0
    n_decayed_in_mountain = 0
    n_with_decay = 0

    @testset "Propagation and decay-in-mountain fractions" begin
        for (j, fs) in enumerate(fstates)
            losses, cont_e, secs, prop_final = proposal_propagate(fs, prem, bvh, j)
            
            # Culled event: lepton exited all media without propagating
            # (vertex off-mesh / above the atmosphere). Skip.
            isnan(prop_final.energy) && continue

            in_air = isinair_prop(prop_final, prem, bvh)
            has_decay = !isempty(secs)

            if in_air
                n_emerged_air += 1
            end

            if has_decay
                n_with_decay += 1
                if !in_air
                    n_decayed_in_mountain += 1
                end
            end
        end

        frac_reached_proposal = n_successful / n_injected
        frac_emerged_air = n_emerged_air / n_successful
        frac_with_decay = n_with_decay / n_successful
        frac_decayed_in_mountain = n_decayed_in_mountain / n_successful

        # A reasonable fraction of injected events should produce a charged lepton
        @test frac_reached_proposal > 0.3
        @test frac_reached_proposal < 0.8

        # Most propagated taus should decay (PROPOSAL handles decay)
        @test frac_with_decay > 0.9

        # The majority of decays should happen inside the mountain.
        # Threshold is relaxed vs full mesh since the decimated test geometry
        # has gaps that allow more taus to exit.
        @test frac_decayed_in_mountain > 0.7

        # Only a small fraction should emerge in air
        @test frac_emerged_air < 0.5

        # Decayed-in-mountain + emerged-in-air should account for ~all decays
        # (some events may lose all energy without decaying, but most should decay)
        @test frac_decayed_in_mountain + frac_emerged_air > 0.8
    end
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Propagation Decay Fraction" begin
        run_propagation_decay_fraction_tests()
    end
end
