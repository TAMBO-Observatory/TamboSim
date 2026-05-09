include("testsetup.jl")
"""
Tests for the weighting module including weight parameters and calculations.

These tests use the actual TamboSim types from src/ to ensure code coverage.
"""

# Import weighting-related types and functions
import TamboSim: null_params, p_mc, p_phys, _oneweight_from_ps

# ============================================================================
# Weighting helper functions for testing
# ============================================================================

"""
Calculate power law PDF value.
"""
function test_pl_pdf(γ, emin, emax, e)
    if γ == 1
        norm = 1 / (emin * log(emax / emin))
    else
        mg = 1 - γ
        norm = mg / (emin^γ * (emax^mg - emin^mg))
    end
    return norm * (e / emin)^(-γ)
end

"""
Calculate solid angle.
"""
function test_solid_angle(θmin, θmax, ϕmin, ϕmax)
    return (ϕmax - ϕmin) * (cos(θmin) - cos(θmax))
end

"""
Calculate Monte Carlo probability density.
"""
function test_p_mc(
    area,
    emin,
    emax,
    gamma,
    thetamin,
    thetamax,
    phimin,
    phimax,
    generated_initial_e,
    generated_cd,
    generated_density,
    generated_xs,
    generated_diff_xs
)
    if generated_initial_e == 0.0u"GeV"
        return 0.0u"GeV^-1 * m^-3"
    end

    # Power law PDF
    pdf_e = test_pl_pdf(gamma, emin, emax, generated_initial_e)

    # Solid angle
    Ω = test_solid_angle(thetamin, thetamax, phimin, phimax)

    # MC probability
    p = pdf_e / area / Ω

    return p
end

function test_p_mc(wp::WeightParameters)
    return test_p_mc(
        wp.area,
        wp.emin,
        wp.emax,
        wp.gamma,
        wp.thetamin,
        wp.thetamax,
        wp.phimin,
        wp.phimax,
        wp.generated_initial_e,
        wp.generated_cd,
        wp.generated_density,
        wp.generated_xs,
        wp.generated_diff_xs
    )
end

"""
Calculate physical probability density (interaction probability per unit length).
"""
function test_p_phys(
    physical_cd,
    physical_density,
    physical_diff_xs
)
    if isnan(ustrip(physical_cd))
        return 0.0u"m^-1"
    end

    # Simple interaction probability per unit length
    # P/L = n * σ where n is number density (1/volume)
    # n = ρ * N_A / M, where N_A/M ≈ 6e23 / (1 g) for hydrogen-like target
    # For simplicity, use an approximate N_A/M factor
    N_A_over_M = 6.022e23u"g^-1"  # Avogadro's number per gram

    # P/L = ρ * (N_A/M) * σ has units: (g/cm^3) * (1/g) * cm^2 = cm^-1 -> m^-1
    p = physical_density * N_A_over_M * physical_diff_xs |> u"m^-1"

    return abs(p)
end

# ============================================================================
# Test functions
# ============================================================================

function run_weighting_tests()
    @testset "Weight Parameters" begin
        test_weight_parameters_construction()
        test_null_weight_parameters()
    end

    @testset "Monte Carlo Probability" begin
        test_p_mc_basic()
        test_p_mc_with_weight_params()
        test_p_mc_zero_energy()
    end

    @testset "Physical Probability" begin
        test_p_phys_basic()
        test_p_phys_nan_cd()
    end

    @testset "PhaseSpace functors" begin
        test_forced_neutrino_functor_matches_old_formula()
        test_upstream_neutrino_functor_matches_old_formula()
        test_cr_functor_matches_old_formula()
        test_compatibility_pdg_mismatch()
        test_compatibility_geometry_mismatch()
        test_compatibility_missing_geometry_hash()
        test_compatibility_energy_out_of_bounds()
    end

    @testset "Multi-campaign oneweight" begin
        test_disjoint_phase_spaces()
        test_boundary_disjoint_phase_spaces()
        test_overlapping_phase_spaces()
    end
end

# Weight Parameters tests
function test_weight_parameters_construction()
    wp = WeightParameters(
        100.0u"m^2",      # area
        1.0u"GeV",        # emin
        1000.0u"GeV",     # emax
        2.0,              # gamma
        0.0,              # thetamin
        Float64(π/2),     # thetamax
        0.0,              # phimin
        Float64(2π),      # phimax
        100.0u"GeV",      # generated_initial_e
        50.0u"GeV",       # generated_final_e
        100.0u"g/cm^2",   # generated_cd
        2.65u"g/cm^3",    # generated_density
        1e-36u"cm^2",     # generated_xs
        1e-37u"cm^2"      # generated_diff_xs
    )

    @test wp.area == 100.0u"m^2"
    @test wp.emin == 1.0u"GeV"
    @test wp.emax == 1000.0u"GeV"
    @test wp.gamma == 2.0
    @test wp.generated_initial_e == 100.0u"GeV"
end

function test_null_weight_parameters()
    null_wp = null_params

    @test isnan(ustrip(null_wp.area))
    @test isnan(ustrip(null_wp.emin))
    @test isnan(ustrip(null_wp.generated_initial_e))
end

# Monte Carlo Probability tests
function test_p_mc_basic()
    # Test basic p_mc calculation
    p = test_p_mc(
        100.0u"m^2",      # area
        1.0u"GeV",        # emin
        1000.0u"GeV",     # emax
        2.0,              # gamma
        0.0,              # thetamin
        Float64(π/2),     # thetamax
        0.0,              # phimin
        Float64(2π),      # phimax
        100.0u"GeV",      # generated_initial_e
        100.0u"g/cm^2",   # generated_cd
        2.65u"g/cm^3",    # generated_density
        1e-36u"cm^2",     # generated_xs
        1e-37u"cm^2"      # generated_diff_xs
    )

    @test !isnan(ustrip(p))
    @test p > 0.0u"GeV^-1 * m^-2"
end

function test_p_mc_with_weight_params()
    wp = WeightParameters(
        100.0u"m^2",
        1.0u"GeV",
        1000.0u"GeV",
        2.0,
        0.0,
        Float64(π/2),
        0.0,
        Float64(2π),
        100.0u"GeV",
        50.0u"GeV",
        100.0u"g/cm^2",
        2.65u"g/cm^3",
        1e-36u"cm^2",
        1e-37u"cm^2"
    )

    p = test_p_mc(wp)

    @test !isnan(ustrip(p))
    @test p >= 0.0u"GeV^-1 * m^-2"
end

function test_p_mc_zero_energy()
    # Zero energy should return zero probability
    p = test_p_mc(
        100.0u"m^2",
        1.0u"GeV",
        1000.0u"GeV",
        2.0,
        0.0,
        Float64(π/2),
        0.0,
        Float64(2π),
        0.0u"GeV",        # Zero initial energy
        100.0u"g/cm^2",
        2.65u"g/cm^3",
        1e-36u"cm^2",
        1e-37u"cm^2"
    )

    @test p == 0.0u"GeV^-1 * m^-3"
end

# Physical Probability tests
function test_p_phys_basic()
    p = test_p_phys(
        100.0u"g/cm^2",   # physical_cd
        2.65u"g/cm^3",    # physical_density
        1e-36u"cm^2"      # physical_diff_xs
    )

    @test !isnan(ustrip(p))
    @test p >= 0.0u"m^-1"
end

function test_p_phys_nan_cd()
    # NaN column depth should return zero probability
    p = test_p_phys(
        NaN * u"g/cm^2",
        2.65u"g/cm^3",
        1e-36u"cm^2"
    )

    @test p == 0.0u"m^-1"
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

    mc   = p_mc(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π,
                1e4u"GeV", 100.0u"g/cm^2", 2.65u"g/cm^3", 2e-36u"cm^2", 7e-38u"cm^2")
    phys = p_phys(100.0u"g/cm^2", 2.65u"g/cm^3", 7e-38u"cm^2")
    expected = uconvert(u"GeV^-1 * m^-2 * sr^-1", mc / phys)

    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈ ustrip(u"GeV^-1 * m^-2 * sr^-1", expected)
end

function test_upstream_neutrino_functor_matches_old_formula()
    g  = _mock_g_frame()
    ps = _test_neutrino_ps(g)
    pt = UpstreamNeutrinoInteractionPoint(g, 16, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")

    result = ps(pt)

    mc_surface = p_mc(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π,
                      1e4u"GeV", NaN*u"g/cm^2", NaN*u"g/cm^3", NaN*u"cm^2", NaN*u"cm^2")
    # p_mc with NaN cd falls back to dividing by 1cm — that's the old surface path
    # Instead verify against _surface_pdf formula directly
    @test result > 0.0u"GeV^-1 * m^-2 * sr^-1"
    @test !isnan(ustrip(result))
    # Surface case: no interaction terms, so result equals p_mc_surface
    wp = WeightParameters(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π,
                          1e4u"GeV", NaN*u"GeV", NaN*u"g/cm^2", NaN*u"g/cm^3",
                          NaN*u"cm^2", NaN*u"cm^2")
    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈
          ustrip(u"GeV^-1 * m^-2 * sr^-1", uconvert(u"GeV^-1 * m^-2 * sr^-1", p_mc_surface(wp)))
end

function test_cr_functor_matches_old_formula()
    g  = _mock_g_frame()
    ps = _test_cr_ps(g)
    pt = SurfaceCRPoint(g, 2212, 1e4u"GeV", π/4, 1.0, 500.0u"m^2")

    result = ps(pt)

    wp = WeightParameters(500.0u"m^2", 1e3u"GeV", 1e6u"GeV", 2.0, 0.0, π/2, 0.0, 2π,
                          1e4u"GeV", NaN*u"GeV", NaN*u"g/cm^2", NaN*u"g/cm^3",
                          NaN*u"cm^2", NaN*u"cm^2")
    @test ustrip(u"GeV^-1 * m^-2 * sr^-1", result) ≈
          ustrip(u"GeV^-1 * m^-2 * sr^-1", uconvert(u"GeV^-1 * m^-2 * sr^-1", p_mc_surface(wp)))
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
