include("testsetup.jl")
"""
Tests for the weighting module: PhaseSpace / PhaseSpacePoint functors and the
multi-campaign one-weight aggregator.
"""

import TamboSim: _oneweight_from_ps

# =============================================================================
# Pre-refactor reference formulas
#
# The functor methods in `phase_space.jl` were derived from the (now deleted)
# `p_mc`, `p_phys`, and `p_mc_surface` helpers. The `*_matches_old_formula`
# tests below pin the new implementation to those old formulas; reproducing
# them here as test-local helpers means the regression test still has a
# documented reference even though the production code no longer carries it.
# =============================================================================

function _old_mc_density(area, emin, emax, gamma, thetamin, thetamax, phimin, phimax,
                         E, cd, density, sigma, dsigma)
    norm = pl_norm(gamma, emin, emax)
    p = norm * (E / emin)^(-gamma)
    Ω = (cos(thetamin) - cos(thetamax)) * (phimax - phimin) * u"sr"
    p /= Ω
    p /= area
    p *= density / cd
    p *= dsigma / sigma
    return p
end

function _old_phys_density(cd, density, dsigma)
    miso = TamboSim.speedoflight^(-2) * (938.27208816u"MeV" + 939.5654133u"MeV") / 2
    p  = cd / miso
    p *= density / cd
    p *= dsigma
    return p
end

function _old_surface_density(area, emin, emax, gamma, thetamin, thetamax, phimin, phimax, E)
    norm = pl_norm(gamma, emin, emax)
    p = norm * (E / emin)^(-gamma)
    Ω = (cos(thetamin) - cos(thetamax)) * (phimax - phimin) * u"sr"
    p /= Ω
    p /= area
    return uconvert(u"GeV^-1 * m^-2 * sr^-1", p)
end

# ============================================================================
# Test runner
# ============================================================================

function run_weighting_tests()
    @testset "PhaseSpace functors" begin
        test_forced_neutrino_functor_matches_old_formula()
        test_upstream_neutrino_functor_matches_old_formula()
        test_cr_functor_matches_old_formula()
        test_compatibility_energy_out_of_bounds()
        test_compatibility_phi_wraparound()
    end

    @testset "Campaign-level compatibility (M ↔ PS filter)" begin
        test_campaign_pdg_mismatch_via_filter()
        test_campaign_geometry_mismatch_via_filter()
    end

    @testset "Multi-campaign oneweight" begin
        test_disjoint_phase_spaces()
        test_boundary_disjoint_phase_spaces()
        test_overlapping_phase_spaces()
    end

    @testset "Round-trip oneweights from example_output" begin
        test_round_trip_oneweights_match_inline_formula()
    end
end

# =============================================================================
# PhaseSpace / PhaseSpacePoint tests
# =============================================================================

const _TEST_GEOM_HASH = UInt(42)

function _test_neutrino_ps(; emin=1e3, emax=1e6, nevent=1000,
                            geometry_hash::UInt=_TEST_GEOM_HASH, pdg::Int=16)
    NeutrinoInjectionPS(geometry_hash, pdg, emin*u"GeV", emax*u"GeV",
                        2.0, 0.0, π/2, 0.0, 2π, nevent)
end

function _test_cr_ps(; emin=1e3, emax=1e6, nevent=1000,
                      geometry_hash::UInt=_TEST_GEOM_HASH, pdg::Int=2212)
    CosmicRayInjectionPS(geometry_hash, pdg, emin*u"GeV", emax*u"GeV",
                         2.0, 0.0, π/2, 0.0, 2π, nevent)
end

function test_forced_neutrino_functor_matches_old_formula()
    ps = _test_neutrino_ps()
    # Distinct sigma vs dsigma so a swap between the two would actually fail.
    pt = ForcedNeutrinoInteractionPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2",
                                        100.0u"g/cm^2", 2.65u"g/cm^3",
                                        2e-36u"cm^2", 7e-38u"cm^2")

    result = ps(pt)

    mc   = _old_mc_density(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π,
                           1e4u"GeV", 100.0u"g/cm^2", 2.65u"g/cm^3", 2e-36u"cm^2", 7e-38u"cm^2")
    phys = _old_phys_density(100.0u"g/cm^2", 2.65u"g/cm^3", 7e-38u"cm^2")
    expected = uconvert(u"GeV^-1 * m^-2 * sr^-1", mc / phys)

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_upstream_neutrino_functor_matches_old_formula()
    ps = _test_neutrino_ps()
    pt = UpstreamNeutrinoInteractionPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2")

    result = ps(pt)
    expected = _old_surface_density(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π, 1e4u"GeV")

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_cr_functor_matches_old_formula()
    ps = _test_cr_ps()
    pt = SurfaceCRPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2")

    result = ps(pt)
    expected = _old_surface_density(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π, 1e4u"GeV")

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_compatibility_energy_out_of_bounds()
    ps = _test_cr_ps(; emin=1e3, emax=1e5)
    pt = SurfaceCRPoint(1e6u"GeV", π/4, 1.0, 500.0u"m^2")
    @test ps(pt) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

function test_compatibility_phi_wraparound()
    # The injection sampler accepts a φ range that wraps past 2π (e.g.
    # [3π/2, 5π/2], i.e. 270°→90° through 0°). cart_to_sph returns φ in
    # [-π, π], so an event at φ = -π/2 must still match this range.
    ps = CosmicRayInjectionPS(_TEST_GEOM_HASH, 2212, 1e3u"GeV", 1e6u"GeV", 2.0,
                              0.0, π/2, 3π/2, 5π/2, 1000)
    # In-range: φ = -π/2 is the same direction as 3π/2.
    pt_in = SurfaceCRPoint(1e4u"GeV", π/4, -π/2, 500.0u"m^2")
    @test ps(pt_in) > 0.0u"GeV^-1 * m^-2 * sr^-1"
    # Out of range: φ = π is opposite to the [3π/2, 5π/2] arc.
    pt_out = SurfaceCRPoint(1e4u"GeV", π/4, Float64(π), 500.0u"m^2")
    @test ps(pt_out) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

# Campaign-level filter: pdg and geometry_hash live on M's "injection"
# config snapshot under E2; mismatches drop the PS from `_oneweight_from_ps`
# before the per-event functor runs.
function test_campaign_pdg_mismatch_via_filter()
    ps = _test_cr_ps(; pdg=2212)
    pt = SurfaceCRPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    # M says pdg=9999 — PS describing pdg=2212 must not contribute.
    q  = _make_q_frame_with_point(pt; pdg=9999)
    @test _oneweight_from_ps(q, PhaseSpace[ps]) == 0.0u"GeV*m^2*sr"
end

function test_campaign_geometry_mismatch_via_filter()
    ps = _test_cr_ps(; geometry_hash=UInt(1))
    pt = SurfaceCRPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    # M's snapshot says geometry_hash=2 — PS for geometry_hash=1 must not contribute.
    q  = _make_q_frame_with_point(pt; geometry_hash=UInt(2))
    @test _oneweight_from_ps(q, PhaseSpace[ps]) == 0.0u"GeV*m^2*sr"
end

# =============================================================================
# Multi-campaign oneweight tests
# =============================================================================

function _make_q_frame_with_point(pt::PhaseSpacePoint;
                                   geometry_hash::UInt=_TEST_GEOM_HASH,
                                   pdg::Int=2212)
    cfg = Dict{String,Any}("geometry_hash" => geometry_hash, "pdg" => pdg)
    m   = Frame('M', Dict{String,Any}("injection" => cfg))
    return Frame('Q', Dict{String,Any}("phase_space_point" => pt),
                 Dict{Char,Frame}('M' => m))
end

function test_disjoint_phase_spaces()
    ps1 = _test_cr_ps(; emin=1e3, emax=1e5, nevent=1000)
    ps2 = _test_cr_ps(; emin=1e5, emax=1e7, nevent=1000)

    # Event only in ps1's range
    pt_low = SurfaceCRPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    q_low  = _make_q_frame_with_point(pt_low)
    ow_combined = _oneweight_from_ps(q_low, PhaseSpace[ps1, ps2])
    ow_single   = _oneweight_from_ps(q_low, PhaseSpace[ps1])
    @test ustrip(u"GeV*m^2*sr", ow_combined) ≈ ustrip(u"GeV*m^2*sr", ow_single)

    # Event only in ps2's range
    pt_high = SurfaceCRPoint(1e6u"GeV", π/4, 1.0, 500.0u"m^2")
    q_high  = _make_q_frame_with_point(pt_high)
    ow_combined2 = _oneweight_from_ps(q_high, PhaseSpace[ps1, ps2])
    ow_single2   = _oneweight_from_ps(q_high, PhaseSpace[ps2])
    @test ustrip(u"GeV*m^2*sr", ow_combined2) ≈ ustrip(u"GeV*m^2*sr", ow_single2)
end

function test_boundary_disjoint_phase_spaces()
    # Adjacent campaigns sharing a boundary energy: with half-open intervals
    # (`emin <= E < emax`), an event at exactly E == emax_PS1 == emin_PS2 must
    # belong to PS2 only — never both. Catches regressions to inclusive `<=`.
    ps1 = _test_cr_ps(; emin=1e3, emax=1e5, nevent=1000)
    ps2 = _test_cr_ps(; emin=1e5, emax=1e7, nevent=1000)

    pt_boundary = SurfaceCRPoint(1e5u"GeV", π/4, 1.0, 500.0u"m^2")
    q_boundary  = _make_q_frame_with_point(pt_boundary)

    ow_combined = _oneweight_from_ps(q_boundary, PhaseSpace[ps1, ps2])
    ow_only_ps2 = _oneweight_from_ps(q_boundary, PhaseSpace[ps2])
    @test ustrip(u"GeV*m^2*sr", ow_combined) ≈ ustrip(u"GeV*m^2*sr", ow_only_ps2)

    # PS1 alone must reject the boundary event (zero contribution → infinite ow → _zero_ow sentinel).
    @test ps1(pt_boundary) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

function test_overlapping_phase_spaces()
    ps1 = _test_cr_ps(; emin=1e3, emax=1e6, nevent=1000)
    ps2 = _test_cr_ps(; emin=1e5, emax=1e7, nevent=1000)

    # Event outside overlap (only in ps1)
    pt_low = SurfaceCRPoint(1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    q_low  = _make_q_frame_with_point(pt_low)
    ow_combined = _oneweight_from_ps(q_low, PhaseSpace[ps1, ps2])
    ow_single   = _oneweight_from_ps(q_low, PhaseSpace[ps1])
    @test ustrip(u"GeV*m^2*sr", ow_combined) ≈ ustrip(u"GeV*m^2*sr", ow_single)

    # Event in overlap — both campaigns contribute, oneweight should be smaller
    pt_overlap = SurfaceCRPoint(5e5u"GeV", π/4, 1.0, 500.0u"m^2")
    q_overlap  = _make_q_frame_with_point(pt_overlap)
    ow_both  = _oneweight_from_ps(q_overlap, PhaseSpace[ps1, ps2])
    ow_ps1   = _oneweight_from_ps(q_overlap, PhaseSpace[ps1])
    ow_ps2   = _oneweight_from_ps(q_overlap, PhaseSpace[ps2])
    @test ustrip(u"GeV*m^2*sr", ow_both) < ustrip(u"GeV*m^2*sr", ow_ps1)
    @test ustrip(u"GeV*m^2*sr", ow_both) < ustrip(u"GeV*m^2*sr", ow_ps2)

    # Verify exact value: 1 / (ps1(pt)*n1 + ps2(pt)*n2)
    contribution1 = ps1(pt_overlap) * ps1.nevent
    contribution2 = ps2(pt_overlap) * ps2.nevent
    expected = uconvert(u"GeV*m^2*sr", inv(contribution1 + contribution2))
    @test ustrip(u"GeV*m^2*sr", ow_both) ≈ ustrip(u"GeV*m^2*sr", expected)
end

# =============================================================================
# Round-trip test against the committed example_output.jld2 fixture.
#
# Loads geometry + example_output, calls `oneweights(tf)`, and recomputes the
# expected per-event one-weight inline from the PS + Point fields using the
# pre-refactor formula helpers. Catches any drift between the production
# functor body and the formulas the test helpers pin.
# =============================================================================

function test_round_trip_oneweights_match_inline_formula()
    tambo_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    geom_file  = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
    out_file   = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

    tf = load_frames([geom_file, out_file])
    @test length(tf.q_frames) > 0
    @test length(tf.m_frames) == 1

    ows = oneweights(tf)
    @test length(ows) == length(tf.q_frames)

    ps = TamboSim.build_phase_space(tf.m_frames[1])
    @test ps isa NeutrinoInjectionPS

    n_checked = 0
    for (q, ow) in zip(tf.q_frames, ows)
        haskey(q.data, "phase_space_point") || continue
        pt = q["phase_space_point"]

        # Recompute ps(pt) inline from the relevant `_old_*` helper, depending
        # on which Point flavor this event produced. This is the formula the
        # production functor was derived from; the round-trip test catches
        # drift between them.
        expected_density = if pt isa ForcedNeutrinoInteractionPoint
            mc   = _old_mc_density(pt.area, ps.emin, ps.emax, ps.gamma,
                                   ps.thetamin, ps.thetamax, ps.phimin, ps.phimax,
                                   pt.E, pt.cd, pt.rho, pt.sigma, pt.dsigma)
            phys = _old_phys_density(pt.cd, pt.rho, pt.dsigma)
            uconvert(u"GeV^-1 * m^-2 * sr^-1", mc / phys)
        elseif pt isa UpstreamNeutrinoInteractionPoint
            _old_surface_density(pt.area, ps.emin, ps.emax, ps.gamma,
                                 ps.thetamin, ps.thetamax, ps.phimin, ps.phimax, pt.E)
        else
            error("unexpected Point type in fixture: $(typeof(pt))")
        end

        expected_ow = uconvert(u"GeV*m^2*sr", inv(expected_density * ps.nevent))
        @test ustrip(u"GeV*m^2*sr", ow) ≈ ustrip(u"GeV*m^2*sr", expected_ow)
        n_checked += 1
    end
    @test n_checked > 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Weighting" begin
        run_weighting_tests()
    end
end
