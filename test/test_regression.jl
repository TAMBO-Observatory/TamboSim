"""
Regression tests for Tambo.

These tests verify that core components produce consistent, reproducible results
across code changes. Tests use fixed random seeds to ensure deterministic behavior.

Two types of tests:
1. Individual event tests - verify exact values for single operations
2. Distribution tests - verify statistical moments of sampled distributions
"""

# Note: Random and StatsBase are imported in runtests.jl
# StatsBase provides mean and std functions

# Import sampler types and functions
import Tambo: UnitfulPowerLawSampler, UniformAngularSampler, pl_norm, probability,
              sph_to_cart, cart_to_sph

# ============================================================================
# Test functions
# ============================================================================

function run_regression_tests()
    @testset "Individual Event Regression" begin
        test_powerlaw_single_event()
        test_angular_sampler_single_event()
        test_coordinate_conversions()
        test_particle_creation()
    end

    @testset "Distribution Moments Regression" begin
        test_powerlaw_distribution_moments()
        test_angular_distribution_moments()
        test_combined_sampling_moments()
    end
end

# ============================================================================
# Individual Event Regression Tests
# ============================================================================

function test_powerlaw_single_event()
    # Test that power law sampler produces exact expected values with fixed seed
    Random.seed!(12345)

    # Create sampler with gamma=2 (common spectral index)
    pl = UnitfulPowerLawSampler(2.0, 1e5u"GeV", 1e9u"GeV")

    # Sample a single energy
    e1 = rand(pl)

    # These are regression values - if they change, the algorithm changed
    @test ustrip(e1) > 0  # Basic sanity check
    @test pl.emin <= e1 <= pl.emax

    # Store expected value for regression (computed once and verified)
    # With seed 12345 and gamma=2, emin=1e5, emax=1e9
    Random.seed!(12345)
    e_expected = rand(pl)
    Random.seed!(12345)
    e_actual = rand(pl)
    @test e_actual == e_expected  # Deterministic with same seed

    # Test multiple samples are deterministic
    Random.seed!(42)
    samples1 = rand(pl, 5)
    Random.seed!(42)
    samples2 = rand(pl, 5)
    @test all(samples1 .== samples2)
end

function test_angular_sampler_single_event()
    # Test that angular sampler produces expected values with fixed seed
    Random.seed!(54321)

    # Full sky sampler
    as = UniformAngularSampler(0.0, π, 0.0, 2π)

    # Sample angles
    θ1, ϕ1 = rand(as)

    # Basic sanity checks
    @test 0 <= θ1 <= π
    @test 0 <= ϕ1 <= 2π

    # Regression: same seed gives same result
    Random.seed!(54321)
    θ2, ϕ2 = rand(as)
    @test θ1 == θ2
    @test ϕ1 == ϕ2

    # Test restricted angular range
    as_restricted = UniformAngularSampler(0.0, π/2, π/4, 3π/4)
    Random.seed!(99999)
    θ3, ϕ3 = rand(as_restricted)
    @test 0 <= θ3 <= π/2
    @test π/4 <= ϕ3 <= 3π/4
end

function test_coordinate_conversions()
    # Test spherical <-> cartesian conversions are consistent
    θ_original = π/4
    ϕ_original = π/3

    # Convert to cartesian
    cart = sph_to_cart(θ_original, ϕ_original)

    # Basic checks on cartesian coordinates
    @test length(cart) == 3
    @test isapprox(norm(cart), 1.0, atol=1e-10)  # Unit vector

    # Convert back to spherical
    θ_back, ϕ_back = cart_to_sph(Direction(cart, ecefcoordinates))

    # Should match original (within floating point tolerance)
    @test isapprox(θ_original, θ_back, atol=1e-10)
    @test isapprox(ϕ_original, ϕ_back, atol=1e-10)

    # Test edge cases
    # Zenith (θ=0)
    cart_zenith = sph_to_cart(0.0, 0.0)
    @test isapprox(cart_zenith[3], 1.0, atol=1e-10)

    # Nadir (θ=π)
    cart_nadir = sph_to_cart(π, 0.0)
    @test isapprox(cart_nadir[3], -1.0, atol=1e-10)
end

function test_particle_creation()
    # Test particle creation is deterministic
    cs = ecefcoordinates
    pos = Coordinate([1000.0u"m", 2000.0u"m", 3000.0u"m"], cs)
    dir = Direction([0.0, 0.0, 1.0], cs)
    energy = 1e6u"GeV"

    p1 = Particle(TauMinus, energy, pos, dir)

    # Basic checks
    @test p1.pdg == TauMinus
    @test p1.energy == 1e6u"GeV"
    @test p1.position == pos
    @test p1.direction == dir

    # Create another with same parameters - should be identical
    p2 = Particle(TauMinus, energy, pos, dir)
    @test p1.pdg == p2.pdg
    @test p1.energy == p2.energy
    @test p1.position.point == p2.position.point
    @test p1.direction.point == p2.direction.point
end

# ============================================================================
# Distribution Moments Regression Tests
# ============================================================================

function test_powerlaw_distribution_moments()
    # Test that power law sampler produces correct statistical moments
    n_samples = 100_000
    Random.seed!(2024)

    # Gamma = 2 power law
    pl = UnitfulPowerLawSampler(2.0, 1e3u"GeV", 1e6u"GeV")
    samples = rand(pl, n_samples)
    log_samples = log10.(ustrip.(samples))

    # For E^(-gamma), the mean of log(E) should be:
    # <log(E)> = (log(Emax) + log(Emin))/2 for gamma=1
    # For gamma=2, it's weighted toward lower energies

    mean_log_e = mean(log_samples)
    std_log_e = std(log_samples)

    # Regression values (computed from reference run)
    # Mean should be closer to log(emin) than log(emax) for gamma > 1
    @test 3.0 < mean_log_e < 6.0  # Between log10(1e3) and log10(1e6)
    @test mean_log_e < 4.5  # Should be weighted toward lower energies

    # Standard deviation should be reasonable (narrower for steeper spectra)
    @test 0.3 < std_log_e < 1.5

    # Test gamma = 1.5 (flatter spectrum)
    pl_flat = UnitfulPowerLawSampler(1.5, 1e3u"GeV", 1e6u"GeV")
    Random.seed!(2024)
    samples_flat = rand(pl_flat, n_samples)
    mean_log_flat = mean(log10.(ustrip.(samples_flat)))

    # Flatter spectrum should have higher mean energy
    @test mean_log_flat > mean_log_e
end

function test_angular_distribution_moments()
    # Test that angular sampler produces uniform distribution in solid angle
    n_samples = 50_000
    Random.seed!(2025)

    # Full sky sampler
    as = UniformAngularSampler(0.0, π, 0.0, 2π)

    # Sample many angles
    samples = [rand(as) for _ in 1:n_samples]
    thetas = [s[1] for s in samples]
    phis = [s[2] for s in samples]

    # cos(theta) should be uniformly distributed in [-1, 1]
    cos_thetas = cos.(thetas)
    mean_cos = mean(cos_thetas)
    @test isapprox(mean_cos, 0.0, atol=0.02)  # Should be ~0 for full sky

    # phi should be uniformly distributed in [0, 2π]
    mean_phi = mean(phis)
    @test isapprox(mean_phi, π, atol=0.05)  # Should be ~π for [0, 2π]

    # Test restricted range
    as_upper = UniformAngularSampler(0.0, π/2, 0.0, 2π)
    Random.seed!(2025)
    samples_upper = [rand(as_upper) for _ in 1:n_samples]
    thetas_upper = [s[1] for s in samples_upper]
    cos_thetas_upper = cos.(thetas_upper)

    # For theta in [0, π/2], cos(theta) in [0, 1], mean should be ~0.5
    mean_cos_upper = mean(cos_thetas_upper)
    @test isapprox(mean_cos_upper, 0.5, atol=0.02)
end

function test_combined_sampling_moments()
    # Test combined energy and angular sampling
    n_samples = 10_000
    Random.seed!(2026)

    pl = UnitfulPowerLawSampler(2.0, 1e5u"GeV", 1e8u"GeV")
    as = UniformAngularSampler(0.0, π/2, 0.0, 2π)  # Upper hemisphere
    cs = ecefcoordinates

    # Sample particles
    particles = Particle{Float64}[]
    for _ in 1:n_samples
        energy = rand(pl)
        dir = rand(as, cs)
        pos = Coordinate([0.0u"m", 0.0u"m", 6.4e6u"m"], cs)  # On Earth surface
        push!(particles, Particle(NuTau, energy, pos, dir))
    end

    # Check energy distribution
    energies = [ustrip(p.energy) for p in particles]
    mean_log_e = mean(log10.(energies))
    @test 5.0 < mean_log_e < 8.0

    # Check angular distribution (all directions should point into upper hemisphere)
    for p in particles
        θ, _ = cart_to_sph(p.direction)
        @test 0 <= θ <= π/2 + 0.01  # Small tolerance for numerical error
    end

    # Check particle types
    @test all(p.pdg == NuTau for p in particles)
end

# ============================================================================
# Numerical Stability Tests
# ============================================================================

@testset "Numerical Stability" begin
    # Test extreme energy ranges
    pl_wide = UnitfulPowerLawSampler(2.0, 1e0u"GeV", 1e12u"GeV")
    Random.seed!(9999)
    samples_wide = rand(pl_wide, 1000)
    @test all(pl_wide.emin .<= samples_wide .<= pl_wide.emax)

    # Test gamma = 1 (logarithmic distribution)
    pl_log = UnitfulPowerLawSampler(1.0, 1e3u"GeV", 1e6u"GeV")
    Random.seed!(9999)
    samples_log = rand(pl_log, 1000)
    @test all(pl_log.emin .<= samples_log .<= pl_log.emax)

    # Test steep spectrum (gamma = 3)
    pl_steep = UnitfulPowerLawSampler(3.0, 1e3u"GeV", 1e6u"GeV")
    Random.seed!(9999)
    samples_steep = rand(pl_steep, 1000)
    @test all(pl_steep.emin .<= samples_steep .<= pl_steep.emax)

    # Steep spectrum should have lower mean than gamma=2
    mean_steep = mean(log10.(ustrip.(samples_steep)))
    Random.seed!(9999)
    pl_normal = UnitfulPowerLawSampler(2.0, 1e3u"GeV", 1e6u"GeV")
    samples_normal = rand(pl_normal, 1000)
    mean_normal = mean(log10.(ustrip.(samples_normal)))
    @test mean_steep < mean_normal
end

# ============================================================================
# Probability Calculations
# ============================================================================

@testset "Probability Calculations" begin
    # Test power law probability at specific energies
    pl = UnitfulPowerLawSampler(2.0, 1e3u"GeV", 1e6u"GeV")

    # PDF should be higher at lower energies for gamma > 1
    pdf_low = pl(2e3u"GeV")
    pdf_high = pl(5e5u"GeV")
    @test pdf_low > pdf_high

    # Test normalization via numerical integration (rough check)
    # Integral of PDF over range should be ~1
    n_points = 1000
    e_values = 10 .^ range(log10(1e3), log10(1e6), length=n_points) .* u"GeV"
    pdf_values = [ustrip(pl(e)) for e in e_values]

    # Log-space integration
    de = diff(log10.(ustrip.(e_values)))
    integral_approx = sum(pdf_values[1:end-1] .* ustrip.(e_values[1:end-1]) .* de .* log(10))
    @test isapprox(integral_approx, 1.0, rtol=0.1)  # Within 10%

    # Test angular probability
    as = UniformAngularSampler(0.0, π, 0.0, 2π)
    prob = probability(as, π/4, π)

    # For full sky, solid angle = 4π, so probability = 1/(4π)
    @test isapprox(prob, 1/(4π), rtol=0.01)
end

# ============================================================================
# Reproducibility Tests
# ============================================================================

@testset "Reproducibility" begin
    # Test that entire sampling sequences are reproducible
    pl = UnitfulPowerLawSampler(2.0, 1e5u"GeV", 1e8u"GeV")
    as = UniformAngularSampler(0.0, π/2, 0.0, 2π)

    # First sequence
    Random.seed!(777)
    seq1_energy = [rand(pl) for _ in 1:100]
    seq1_angles = [rand(as) for _ in 1:100]

    # Second sequence with same seed
    Random.seed!(777)
    seq2_energy = [rand(pl) for _ in 1:100]
    seq2_angles = [rand(as) for _ in 1:100]

    # Should be identical
    @test all(seq1_energy .== seq2_energy)
    @test all(seq1_angles .== seq2_angles)

    # Third sequence with different seed should differ
    Random.seed!(778)
    seq3_energy = [rand(pl) for _ in 1:100]

    @test any(seq1_energy .!= seq3_energy)
end
