include("testsetup.jl")
"""
Unit tests for the custom through-Earth propagation loop
(`src/injection/propagate_through_earth.jl`) and the bounded, density-aware
PROPOSAL segment stepper it drives (`_run_proposal_segments`).

Two things here are regression tests rather than plain unit tests:

- The deep-Earth charged-lepton leg must use PREM shell densities, not
  StandardRock's nominal 2.65 g/cm³. Propagating a tau through the mantle or core
  as though it were crustal rock under-counts the column depth by a factor of a
  few and badly overestimates deep-lepton survival.
- `_run_proposal_segments` must report `:reached_cap` when a distance cap is hit,
  including when the segment list falls a hair short of the cap through
  floating-point drift between two traces of the same geometry.
"""

import TamboSim: _ColumnDepthProfile, _e_of_Xcd, _Xcd_of_e,
              _run_proposal_segments, _prem_segment_densities, _SEGMENT_CAP_TOL,
              deep_propagator, generate_config,
              propagation_anomalies, reset_propagation_anomalies!,
              precompute_detector_properties, inject_neutrino_event, CrossSection,
              init_proposal, ParticleType

const PP = TamboSim.PP
const JSON3 = TamboSim.JSON3

"Synthetic three-segment profile: 2 km at 2.6, 3 km at 5.0, 4 km at 11.0 g/cm³."
function _synthetic_profile()
    e_bkpt = [0.0u"m", 2000.0u"m", 5000.0u"m", 9000.0u"m"]
    ρ = [0.0u"g/cm^3", 2.6u"g/cm^3", 5.0u"g/cm^3", 11.0u"g/cm^3"]
    Xcd = [0.0u"g/cm^2"]
    for k in 2:4
        push!(Xcd, Xcd[k-1] + uconvert(u"g/cm^2", ρ[k] * (e_bkpt[k] - e_bkpt[k-1])))
    end
    return _ColumnDepthProfile(e_bkpt, Xcd, ρ, e_bkpt[end], Xcd[end])
end

function run_propagate_through_earth_tests()

    @testset "Column-depth profile" begin
        prof = _synthetic_profile()

        # Breakpoints must land exactly on the tabulated column depths.
        for k in 1:length(prof.e_bkpt)
            @test _Xcd_of_e(prof, prof.e_bkpt[k]) ≈ prof.Xcd[k] rtol=1e-12
        end

        # Within a segment the profile is linear in the segment density.
        @test _Xcd_of_e(prof, 1000.0u"m") ≈ uconvert(u"g/cm^2", 2.6u"g/cm^3" * 1000.0u"m") rtol=1e-12
        @test _Xcd_of_e(prof, 3500.0u"m") ≈
              prof.Xcd[2] + uconvert(u"g/cm^2", 5.0u"g/cm^3" * 1500.0u"m") rtol=1e-12

        # Round-trip both ways across every segment, including across breakpoints.
        for e in (0.0u"m", 500.0u"m", 2000.0u"m", 3500.0u"m", 5000.0u"m", 7000.0u"m", 9000.0u"m")
            @test _e_of_Xcd(prof, _Xcd_of_e(prof, e)) ≈ e rtol=1e-9 atol=1e-6u"m"
        end
        for f in (0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0)
            X = f * prof.Xcd_total
            @test _Xcd_of_e(prof, _e_of_Xcd(prof, X)) ≈ X rtol=1e-9 atol=1e-6u"g/cm^2"
        end

        # Both maps clamp instead of extrapolating.
        @test _Xcd_of_e(prof, -1.0u"m") == 0.0u"g/cm^2"
        @test _Xcd_of_e(prof, 2 * prof.L_track) == prof.Xcd_total
        @test _e_of_Xcd(prof, -1.0u"g/cm^2") == 0.0u"m"
        @test _e_of_Xcd(prof, 2 * prof.Xcd_total) == prof.L_track

        # A single-density profile must reduce to the analytic chord X = ρ·L.
        ρ0 = 3.3u"g/cm^3"
        L = 12_000.0u"m"
        X0 = uconvert(u"g/cm^2", ρ0 * L)
        uniform = _ColumnDepthProfile([0.0u"m", L], [0.0u"g/cm^2", X0],
                                      [0.0u"g/cm^3", ρ0], L, X0)
        for f in (0.05, 0.3, 0.8)
            @test _Xcd_of_e(uniform, f * L) ≈ f * X0 rtol=1e-12
            @test _e_of_Xcd(uniform, f * X0) ≈ f * L rtol=1e-12
        end
    end

    @testset "Anomaly counters" begin
        reset_propagation_anomalies!()
        @test isempty(propagation_anomalies())
        TamboSim._note_anomaly!(:segments_exhausted)
        TamboSim._note_anomaly!(:segments_exhausted)
        TamboSim._note_anomaly!(:tau_decay_without_nu)
        counts = propagation_anomalies()
        @test counts[:segments_exhausted] == 2
        @test counts[:tau_decay_without_nu] == 1
        # The accessor must hand back a copy, not the live table.
        counts[:segments_exhausted] = 99
        @test propagation_anomalies()[:segments_exhausted] == 2
        reset_propagation_anomalies!()
        @test isempty(propagation_anomalies())
    end

    @testset "PROPOSAL config generation" begin
        # Configs differing only in cuts or density must not collide on one path;
        # a shared path means whichever was written last silently wins.
        nominal = generate_config(15, "StandardRock", 0.5, 0.05, true)
        deep    = generate_config(15, "StandardRock", -1, 1e-3, true)
        dense   = generate_config(15, "StandardRock", -1, 1e-3, true; mass_density=11.0)
        @test length(unique([nominal, deep, dense])) == 3

        parsed = JSON3.read(read(dense, String))
        @test parsed["sectors"][1]["density_distribution"]["mass_density"] == 11.0
        @test !haskey(JSON3.read(read(deep, String))["sectors"][1], :density_distribution)
    end

    # ---- Everything below needs PROPOSAL and the real geometry ----

    tables_path = get_tambosim_path() * "/resources/proposal_tables"
    init_proposal(Dict("tablespath" => tables_path, "vcut" => 0.5))
    if !TamboSim.is_proposal_available()
        @warn "PROPOSAL unavailable; skipping deep-leg propagation tests"
        return
    end

    @testset "Deep propagator uses its density override" begin
        # Caching: same density is one propagator, different densities are not.
        @test deep_propagator(13, 2.65) === deep_propagator(13, 2.65)
        @test deep_propagator(13, 2.65) !== deep_propagator(13, 11.0)

        # The override must actually reach PROPOSAL. Same particle, same seed,
        # same *geometric* distance: denser rock is more column depth, so it must
        # take more energy. This is the regression guard for propagating the deep
        # leg through mantle and core at StandardRock's nominal 2.65 g/cm³.
        function survive(rho, E_MeV, dist_cm)
            PP.set_random_seed(Int32(20260820))
            st = PP.ParticleState(PP.PARTICLE_TYPE_MUMINUS, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
                                  E_MeV; time=0.0, propagated_distance=0.0)
            res = PP.propagate(deep_propagator(13, rho), st;
                               max_distance=dist_cm, min_energy=0.0)
            return PP.get_energy(PP.get_final_state(res))
        end

        e_crust  = survive(2.6,  1e12, 3e5)   # 1e6 GeV muon, 3 km
        e_mantle = survive(5.0,  1e12, 3e5)
        e_core   = survive(11.0, 1e12, 3e5)
        @test e_crust > e_mantle > e_core

        # Not just ordered — the effect is large. Treating core rock as crust
        # would be a multi-fold error in the surviving energy, which is the whole
        # point of the override.
        @test e_crust > 1.5 * e_core
    end

    geometry_path = get_tambosim_path() * "/resources/geometry/colca_valley_3000.jld2"
    frames_geo = load_frames(geometry_path)
    g_frame = TamboSim._get_last_frame(frames_geo, 'G')
    prem = g_frame["prem"]
    bvh  = g_frame["bvh"]

    # A real through-Earth trajectory: take the Earth-entry state of a seeded
    # injection, whose direction points into the Earth by construction.
    d_frame = TamboSim._get_last_frame(frames_geo, 'D')
    cs = g_frame["cs"]
    xs = CrossSection(get_tambosim_path() *
                      "/resources/cross_section_tables/cross_sections.h5:CSMS_nutau")
    detector_props = precompute_detector_properties(g_frame["topography"],
                                                    d_frame["detector_region"])
    as = UniformAngularSampler(deg2rad(0.0), deg2rad(117.0), deg2rad(90.0), deg2rad(290.0))
    pl = UnitfulPowerLawSampler(1.0, 3e5u"GeV", 1e9u"GeV")

    Random.seed!(4242)
    entry = nothing
    for _ in 1:50
        istate, _, _, _ = inject_neutrino_event(16, prem, bvh, cs, d_frame["detector_region"],
                                                as, pl, xs, detector_props; tr_seed=rand(UInt32))
        if !isnan(ustrip(u"GeV", istate.energy))
            entry = istate
            break
        end
    end
    @test entry !== nothing
    entry === nothing && return

    @testset "Deep leg sees PREM densities, not nominal rock" begin
        muon = Particle(ParticleType(13), 1e6u"GeV", entry.position, entry.direction)
        ray = Ray(muon)
        ixs = intersect_all(prem, bvh, ray)
        @test !isempty(ixs)

        ρ = _prem_segment_densities(muon, ixs, prem)
        @test length(ρ) == length(ixs)
        # Every value is a physical PREM density, and none is a stand-in constant.
        @test all(2.5u"g/cm^3" .<= ρ .<= 13.1u"g/cm^3")
        # The trajectory enters the Earth, so at least one segment must be denser
        # than the crust — otherwise the override is not doing anything.
        @test maximum(ρ) > 2.7u"g/cm^3"
    end

    @testset "Bounded segment stepping reports :reached_cap" begin
        muon = Particle(ParticleType(13), 1e7u"GeV", entry.position, entry.direction)
        cap = 1.0u"km"
        _, _, _, final_state, stop_reason =
            _run_proposal_segments(muon, prem, bvh; max_distance=cap, deep=true)

        @test stop_reason == :reached_cap
        @test !isnan(ustrip(u"GeV", final_state.energy))
        travelled = norm((final_state.position - muon.position).point)
        @test travelled ≈ cap rtol=1e-6
        # A cap is a cap: PROPOSAL must not overshoot it.
        @test travelled <= cap + _SEGMENT_CAP_TOL
        # Bounded propagation still costs energy.
        @test final_state.energy < muon.energy

        # An unbounded run over the same ray goes strictly further.
        _, _, _, unbounded, unbounded_reason =
            _run_proposal_segments(muon, prem, bvh; deep=true)
        @test unbounded_reason in (:exited, :decayed)
        @test norm((unbounded.position - muon.position).point) > cap
    end
end
