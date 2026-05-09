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
        test_compatibility_pdg_mismatch()
        test_compatibility_geometry_mismatch()
        test_compatibility_missing_geometry_hash()
        test_compatibility_energy_out_of_bounds()
        test_compatibility_phi_wraparound()
    end

    @testset "Multi-campaign oneweight" begin
        test_disjoint_phase_spaces()
        test_boundary_disjoint_phase_spaces()
        test_overlapping_phase_spaces()
    end
end

# =============================================================================
# PhaseSpace / PhaseSpacePoint tests
# =============================================================================

function _mock_g_frame(hash_val::UInt=UInt(42))
    Frame('G', Dict{String,Any}("geometry_hash" => hash_val))
end

function _test_neutrino_ps(g; emin=1e3, emax=1e6, nevent=1000)
    NeutrinoInjectionPS(g, 16, emin*u"GeV", emax*u"GeV", 2.0, 0.0, π/2, 0.0, 2π, nevent)
end

function _test_cr_ps(g; emin=1e3, emax=1e6, nevent=1000)
    CosmicRayInjectionPS(g, 2212, emin*u"GeV", emax*u"GeV", 2.0, 0.0, π/2, 0.0, 2π, nevent)
end

function test_forced_neutrino_functor_matches_old_formula()
    g  = _mock_g_frame()
    ps = _test_neutrino_ps(g)
    # Distinct sigma vs dsigma so a swap between the two would actually fail.
    pt = ForcedNeutrinoInteractionPoint(g, 16, 1e4u"GeV", π/4, 1.0, 500.0u"m^2", 100.0u"g/cm^2", 2.65u"g/cm^3", 2e-36u"cm^2", 7e-38u"cm^2")

    result = ps(pt)

    mc   = _old_mc_density(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π,
                           1e4u"GeV", 100.0u"g/cm^2", 2.65u"g/cm^3", 2e-36u"cm^2", 7e-38u"cm^2")
    phys = _old_phys_density(100.0u"g/cm^2", 2.65u"g/cm^3", 7e-38u"cm^2")
    expected = uconvert(u"GeV^-1 * m^-2 * sr^-1", mc / phys)

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_upstream_neutrino_functor_matches_old_formula()
    g  = _mock_g_frame()
    ps = _test_neutrino_ps(g)
    pt = UpstreamNeutrinoInteractionPoint(g, 16, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")

    result = ps(pt)
    expected = _old_surface_density(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π, 1e4u"GeV")

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_cr_functor_matches_old_formula()
    g  = _mock_g_frame()
    ps = _test_cr_ps(g)
    pt = SurfaceCRPoint(g, 2212, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")

    result = ps(pt)
    expected = _old_surface_density(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π, 1e4u"GeV")

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_compatibility_pdg_mismatch()
    g  = _mock_g_frame()
    ps = _test_cr_ps(g)
    pt = SurfaceCRPoint(g, 2212+1, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    @test ps(pt) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

function test_compatibility_geometry_mismatch()
    g1 = _mock_g_frame(UInt(1))
    g2 = _mock_g_frame(UInt(2))
    ps = _test_cr_ps(g1)
    pt = SurfaceCRPoint(g2, 2212, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    @test ps(pt) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

function test_compatibility_missing_geometry_hash()
    # Old JLD2 files predate `geometry_hash`; `_compatible` must error loudly
    # rather than silently zeroing out every event in the run.
    g_with    = _mock_g_frame()
    g_without = Frame('G', Dict{String,Any}())
    ps = _test_cr_ps(g_with)
    pt = SurfaceCRPoint(g_without, 2212, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    @test_throws ErrorException ps(pt)
end

function test_compatibility_energy_out_of_bounds()
    g  = _mock_g_frame()
    ps = _test_cr_ps(g; emin=1e3, emax=1e5)
    pt = SurfaceCRPoint(g, 2212, 1e6u"GeV", π/4, 1.0, 500.0u"m^2")
    @test ps(pt) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

function test_compatibility_phi_wraparound()
    # The injection sampler accepts a φ range that wraps past 2π (e.g.
    # [3π/2, 5π/2], i.e. 270°→90° through 0°). cart_to_sph returns φ in
    # [-π, π], so an event at φ = -π/2 must still match this range.
    g  = _mock_g_frame()
    ps = CosmicRayInjectionPS(g, 2212, 1e3u"GeV", 1e6u"GeV", 2.0,
                              0.0, π/2, 3π/2, 5π/2, 1000)
    # In-range: φ = -π/2 is the same direction as 3π/2.
    pt_in = SurfaceCRPoint(g, 2212, 1e4u"GeV", π/4, -π/2, 500.0u"m^2")
    @test ps(pt_in) > 0.0u"GeV^-1 * m^-2 * sr^-1"
    # Out of range: φ = π is opposite to the [3π/2, 5π/2] arc.
    pt_out = SurfaceCRPoint(g, 2212, 1e4u"GeV", π/4, Float64(π), 500.0u"m^2")
    @test ps(pt_out) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

# =============================================================================
# Multi-campaign oneweight tests
# =============================================================================

function _make_q_frame_with_point(pt::PhaseSpacePoint)
    m = Frame('M', Dict{String,Any}())
    return Frame('Q', Dict{String,Any}("phase_space_point" => pt), Dict{Char,Frame}('M' => m))
end

function test_disjoint_phase_spaces()
    g   = _mock_g_frame()
    ps1 = _test_cr_ps(g; emin=1e3, emax=1e5, nevent=1000)
    ps2 = _test_cr_ps(g; emin=1e5, emax=1e7, nevent=1000)

    # Event only in ps1's range
    pt_low = SurfaceCRPoint(g, 2212, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    q_low  = _make_q_frame_with_point(pt_low)
    ow_combined = _oneweight_from_ps(q_low, PhaseSpace[ps1, ps2])
    ow_single   = _oneweight_from_ps(q_low, PhaseSpace[ps1])
    @test ustrip(u"GeV*m^2*sr", ow_combined) ≈ ustrip(u"GeV*m^2*sr", ow_single)

    # Event only in ps2's range
    pt_high = SurfaceCRPoint(g, 2212, 1e6u"GeV", π/4, 1.0, 500.0u"m^2")
    q_high  = _make_q_frame_with_point(pt_high)
    ow_combined2 = _oneweight_from_ps(q_high, PhaseSpace[ps1, ps2])
    ow_single2   = _oneweight_from_ps(q_high, PhaseSpace[ps2])
    @test ustrip(u"GeV*m^2*sr", ow_combined2) ≈ ustrip(u"GeV*m^2*sr", ow_single2)
end

function test_boundary_disjoint_phase_spaces()
    # Adjacent campaigns sharing a boundary energy: with half-open intervals
    # (`emin <= E < emax`), an event at exactly E == emax_PS1 == emin_PS2 must
    # belong to PS2 only — never both. Catches regressions to inclusive `<=`.
    g   = _mock_g_frame()
    ps1 = _test_cr_ps(g; emin=1e3, emax=1e5, nevent=1000)
    ps2 = _test_cr_ps(g; emin=1e5, emax=1e7, nevent=1000)

    pt_boundary = SurfaceCRPoint(g, 2212, 1e5u"GeV", π/4, 1.0, 500.0u"m^2")
    q_boundary  = _make_q_frame_with_point(pt_boundary)

    ow_combined = _oneweight_from_ps(q_boundary, PhaseSpace[ps1, ps2])
    ow_only_ps2 = _oneweight_from_ps(q_boundary, PhaseSpace[ps2])
    @test ustrip(u"GeV*m^2*sr", ow_combined) ≈ ustrip(u"GeV*m^2*sr", ow_only_ps2)

    # PS1 alone must reject the boundary event (zero contribution → infinite ow → _zero_ow sentinel).
    @test ps1(pt_boundary) == 0.0u"GeV^-1 * m^-2 * sr^-1"
end

function test_overlapping_phase_spaces()
    g   = _mock_g_frame()
    ps1 = _test_cr_ps(g; emin=1e3, emax=1e6, nevent=1000)
    ps2 = _test_cr_ps(g; emin=1e5, emax=1e7, nevent=1000)

    # Event outside overlap (only in ps1)
    pt_low = SurfaceCRPoint(g, 2212, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")
    q_low  = _make_q_frame_with_point(pt_low)
    ow_combined = _oneweight_from_ps(q_low, PhaseSpace[ps1, ps2])
    ow_single   = _oneweight_from_ps(q_low, PhaseSpace[ps1])
    @test ustrip(u"GeV*m^2*sr", ow_combined) ≈ ustrip(u"GeV*m^2*sr", ow_single)

    # Event in overlap — both campaigns contribute, oneweight should be smaller
    pt_overlap = SurfaceCRPoint(g, 2212, 5e5u"GeV", π/4, 1.0, 500.0u"m^2")
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

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Weighting" begin
        run_weighting_tests()
    end
end
