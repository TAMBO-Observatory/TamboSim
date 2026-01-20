"""
Tests for the samplers module including power law sampler and angular sampler.
"""

# ============================================================================
# Power Law Sampler for testing
# ============================================================================

struct TestPowerLawSampler{T<:Real}
    γ::T
    emin::Quantity{T, edim, typeof(u"GeV")}
    emax::Quantity{T, edim, typeof(u"GeV")}
    norm::Quantity{T, edim^-1, typeof(u"GeV^-1")}
end

function test_pl_norm(γ, emin, emax)
    if γ == 1
        norm = 1 / (emin * log(emax / emin))
        return norm
    else
        mg = 1 - γ
        norm = mg / (emin^γ * (emax^mg - emin^mg))
        return norm
    end
end

function TestPowerLawSampler(γ::T, emin, emax) where {T}
    norm = test_pl_norm(γ, emin, emax)
    return TestPowerLawSampler{T}(γ, emin, emax, norm)
end

function Base.rand(pl::TestPowerLawSampler{T}) where {T}
    u = rand()
    if pl.γ == 1
        return pl.emin * exp(u / (pl.norm * pl.emin))
    else
        α = 1 - pl.γ
        return (u * α / pl.norm / pl.emin^pl.γ + pl.emin^α)^(1/α)
    end
end

function Base.rand(pl::TestPowerLawSampler{T}, n::Int) where {T}
    return [rand(pl) for _ in 1:n]
end

function (pl::TestPowerLawSampler{T})(e) where {T}
    return pl.norm * (e / pl.emin)^(-pl.γ)
end

# ============================================================================
# Uniform Angular Sampler for testing
# ============================================================================

struct TestAngularSampler
    θmin::Float64
    θmax::Float64
    ϕmin::Float64
    ϕmax::Float64
    function TestAngularSampler(θmin, θmax, ϕmin, ϕmax)
        @assert ϕmin <= ϕmax "ϕmin greater than ϕmax"
        @assert θmin <= θmax "θmin greater than θmax"
        @assert ϕmax - ϕmin <= 2π "Azimuthal range is greater than one period"
        return new(θmin, θmax, ϕmin, ϕmax)
    end
end

function Base.rand(sampler::TestAngularSampler)
    # Uniform in cos(theta)
    θ = acos(rand(Uniform(cos(sampler.θmax), cos(sampler.θmin))))
    ϕ = rand(Uniform(sampler.ϕmin, sampler.ϕmax))
    return θ, ϕ
end

function Base.rand(sampler::TestAngularSampler, cs::TestCoordinateSystem)
    theta, phi = rand(sampler)
    d = test_sph_to_cart(theta, phi)
    return TestDirection(d, cs)
end

function test_angular_probability(sampler::TestAngularSampler, θ, ϕ)
    @assert sampler.θmin <= θ && θ <= sampler.θmax "Zenith angle out of phase space"
    @assert sampler.ϕmin <= ϕ && ϕ <= sampler.ϕmax "Azimuth angle out of phase space"
    Ω = (sampler.ϕmax - sampler.ϕmin) * (cos(sampler.θmin) - cos(sampler.θmax))
    return 1 / Ω
end

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
end

function test_powerlaw_construction()
    emin = 1.0u"GeV"
    emax = 1000.0u"GeV"
    gamma = 2.0

    pl = TestPowerLawSampler(gamma, emin, emax)

    @test pl.γ == gamma
    @test pl.emin == emin
    @test pl.emax == emax
    @test !isnan(pl.norm)
end

function test_powerlaw_normalization()
    emin = 1.0u"GeV"
    emax = 100.0u"GeV"
    gamma = 2.0

    norm = test_pl_norm(gamma, emin, emax)

    @test !isnan(norm)
    @test norm > 0.0u"GeV^-1"
end

function test_powerlaw_sampling()
    emin = 1.0u"GeV"
    emax = 1000.0u"GeV"
    gamma = 2.0

    pl = TestPowerLawSampler(gamma, emin, emax)

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

    pl = TestPowerLawSampler(gamma, emin, emax)

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

    pl = TestPowerLawSampler(gamma, emin, emax)

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

    sampler = TestAngularSampler(θmin, θmax, ϕmin, ϕmax)

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

    sampler = TestAngularSampler(θmin, θmax, ϕmin, ϕmax)

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

    sampler = TestAngularSampler(θmin, θmax, ϕmin, ϕmax)

    # Test probability within range
    θ = π/4
    ϕ = π

    prob = test_angular_probability(sampler, θ, ϕ)

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

    sampler = TestAngularSampler(θmin, θmax, ϕmin, ϕmax)
    cs = test_ecef

    # Sample direction
    direction = rand(sampler, cs)

    @test direction isa TestDirection
    @test norm(direction.point) ≈ 1.0
    @test direction.coordinate_system == cs
end

function test_angular_sampler_edge_cases()
    # Test assertion for invalid ranges
    @test_throws AssertionError TestAngularSampler(π, 0, 0, 2π)  # θmin > θmax
    @test_throws AssertionError TestAngularSampler(0, π, 2π, 0)  # ϕmin > ϕmax
    @test_throws AssertionError TestAngularSampler(0, π, 0, 3π)  # ϕmax - ϕmin > 2π
end
