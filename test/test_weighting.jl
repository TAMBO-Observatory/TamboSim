"""
Tests for the weighting module including weight parameters and calculations.
"""

# ============================================================================
# Weight Parameters for testing
# ============================================================================

struct TestWeightParameters{T<:Real}
    area::Quantity{T, ldim^2, typeof(u"m^2")}
    emin::Quantity{T, edim, typeof(u"GeV")}
    emax::Quantity{T, edim, typeof(u"GeV")}
    gamma::T
    thetamin::T
    thetamax::T
    phimin::T
    phimax::T
    generated_initial_e::Quantity{T, edim, typeof(u"GeV")}
    generated_final_e::Quantity{T, edim, typeof(u"GeV")}
    generated_cd::Quantity{T, mdim/ldim^2, typeof(u"g/cm^2")}
    generated_density::Quantity{T, mdim/ldim^3, typeof(u"g/cm^3")}
    generated_xs::Quantity{T, ldim^2, typeof(u"cm^2")}
    generated_diff_xs::Quantity{T, ldim^2, typeof(u"cm^2")}
end

const test_null_params = TestWeightParameters{Float64}(
    NaN * u"m^2",
    NaN * u"GeV",
    NaN * u"GeV",
    NaN,
    NaN,
    NaN,
    NaN,
    NaN,
    NaN * u"GeV",
    NaN * u"GeV",
    NaN * u"g/cm^2",
    NaN * u"g/cm^3",
    NaN * u"cm^2",
    NaN * u"cm^2"
)

# ============================================================================
# Weighting functions for testing
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

function test_p_mc(wp::TestWeightParameters)
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
end

# Weight Parameters tests
function test_weight_parameters_construction()
    wp = TestWeightParameters(
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
    null_wp = test_null_params

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
    wp = TestWeightParameters(
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
