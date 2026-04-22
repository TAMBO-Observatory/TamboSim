"""
Tests for the samplers module including power law sampler and angular sampler.

These tests use the actual Tambo types from src/ to ensure code coverage.
"""

# Import probability function
import Tambo: probability, pl_norm, find_trim_idxs

# ============================================================================
# Test functions
# ============================================================================

function run_sampler_tests()
    @testset "PowerLaw Sampler" begin
        test_powerlaw_construction()
        test_powerlaw_normalization()
        test_powerlaw_sampling()
        test_powerlaw_pdf()
        test_powerlaw_gamma_one()
    end

    @testset "Uniform Angular Sampler" begin
        test_angular_sampler_construction()
        test_angular_sampler_sampling()
        test_angular_sampler_probability()
        test_angular_sampler_with_coordinate_system()
    end

    @testset "Sampler Edge Cases" begin
        test_angular_sampler_edge_cases()
    end

    @testset "find_trim_idxs" begin
        test_find_trim_idxs_flat()
        test_find_trim_idxs_left_jump()
        test_find_trim_idxs_right_jump()
    end
end

function test_powerlaw_construction()
    emin = 1.0u"GeV"
    emax = 1000.0u"GeV"
    gamma = 2.0

    pl = UnitfulPowerLawSampler(gamma, emin, emax)

    @test pl.γ == gamma
    @test pl.emin == emin
    @test pl.emax == emax
    @test !isnan(pl.norm)
end

function test_powerlaw_normalization()
    emin = 1.0u"GeV"
    emax = 100.0u"GeV"
    gamma = 2.0

    norm = pl_norm(gamma, emin, emax)

    @test !isnan(norm)
    @test norm > 0.0u"GeV^-1"
end

function test_powerlaw_sampling()
    emin = 1.0u"GeV"
    emax = 1000.0u"GeV"
    gamma = 2.0

    pl = UnitfulPowerLawSampler(gamma, emin, emax)

    # Sample multiple energies
    samples = rand(pl, 100)

    @test length(samples) == 100
    @test all(s -> s >= emin && s <= emax, samples)

    # Single sample
    single = rand(pl)
    @test single >= emin
    @test single <= emax
end

function test_powerlaw_pdf()
    emin = 1.0u"GeV"
    emax = 100.0u"GeV"
    gamma = 2.0

    pl = UnitfulPowerLawSampler(gamma, emin, emax)

    # PDF should be higher at lower energies for gamma > 1
    pdf_low = pl(2.0u"GeV")
    pdf_high = pl(50.0u"GeV")

    @test pdf_low > pdf_high
end

function test_powerlaw_gamma_one()
    # Special case: gamma = 1 (logarithmic)
    emin = 1.0u"GeV"
    emax = 100.0u"GeV"
    gamma = 1.0

    pl = UnitfulPowerLawSampler(gamma, emin, emax)

    # Should not throw and should sample correctly
    samples = rand(pl, 10)
    @test length(samples) == 10
    @test all(s -> s >= emin && s <= emax, samples)
end

function test_angular_sampler_construction()
    θmin = 0.0
    θmax = π/2
    ϕmin = 0.0
    ϕmax = 2π

    sampler = UniformAngularSampler(θmin, θmax, ϕmin, ϕmax)

    @test sampler.θmin == θmin
    @test sampler.θmax == θmax
    @test sampler.ϕmin == ϕmin
    @test sampler.ϕmax == ϕmax
end

function test_angular_sampler_sampling()
    θmin = 0.0
    θmax = π/2
    ϕmin = 0.0
    ϕmax = 2π

    sampler = UniformAngularSampler(θmin, θmax, ϕmin, ϕmax)

    # Sample multiple angles
    for _ in 1:100
        θ, ϕ = rand(sampler)
        @test θ >= θmin && θ <= θmax
        @test ϕ >= ϕmin && ϕ <= ϕmax
    end
end

function test_angular_sampler_probability()
    θmin = 0.0
    θmax = π/2
    ϕmin = 0.0
    ϕmax = 2π

    sampler = UniformAngularSampler(θmin, θmax, ϕmin, ϕmax)

    # Test probability within range
    θ = π/4
    ϕ = π

    prob = probability(sampler, θ, ϕ)

    @test !isnan(prob)
    @test prob > 0.0

    # Solid angle for this range: 2π * (cos(0) - cos(π/2)) = 2π
    expected_Ω = 2π * (cos(θmin) - cos(θmax))
    @test prob ≈ 1 / expected_Ω
end

function test_angular_sampler_with_coordinate_system()
    θmin = 0.0
    θmax = π
    ϕmin = 0.0
    ϕmax = 2π

    sampler = UniformAngularSampler(θmin, θmax, ϕmin, ϕmax)
    cs = ecefcoordinates

    # Sample direction using actual Tambo function
    direction = rand(sampler, cs)

    @test direction isa Direction
    @test norm(direction.point) ≈ 1.0
    @test direction.coordinate_system == cs
end

function test_angular_sampler_edge_cases()
    # Test assertion for invalid ranges
    @test_throws AssertionError UniformAngularSampler(π, 0, 0, 2π)  # θmin > θmax
    @test_throws AssertionError UniformAngularSampler(0, π, 2π, 0)  # ϕmin > ϕmax
    @test_throws AssertionError UniformAngularSampler(0, π, 0, 3π)  # ϕmax - ϕmin > 2π
end

function test_find_trim_idxs_flat()
    # Uniform data: no jumps > 1 in log10 space, so lidx=1, ridx=n
    data = [1.0, 2.0, 4.0, 8.0]
    lidx, ridx = find_trim_idxs(data)
    @test lidx == 1
    @test ridx == length(data)
end

function test_find_trim_idxs_left_jump()
    # Large jump at left end
    data = [1.0, 1000.0, 1001.0, 1002.0]
    lidx, ridx = find_trim_idxs(data)
    @test lidx > 1
end

function test_find_trim_idxs_right_jump()
    # Large jump at right end
    data = [1.0, 2.0, 3.0, 3000.0]
    lidx, ridx = find_trim_idxs(data)
    @test ridx < length(data)
end
