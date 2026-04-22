"""
Sampler statistics tests for Tambo.

Verifies that samplers produce correct statistical distributions and that
results are reproducible with fixed seeds. Also covers numerical stability
at extreme parameter values.
"""

import Tambo: UnitfulPowerLawSampler, UniformAngularSampler, pl_norm, probability,
              sph_to_cart, cart_to_sph

function run_sampler_statistics_tests()
    @testset "Individual Event Regression" begin
        test_powerlaw_single_event()
        test_angular_sampler_single_event()
        test_coordinate_conversions()
        test_particle_creation()
    end

    @testset "Distribution Moments" begin
        test_powerlaw_distribution_moments()
        test_angular_distribution_moments()
        test_combined_sampling_moments()
    end

    @testset "Numerical Stability" begin
        # Extreme energy range
        pl_wide = UnitfulPowerLawSampler(2.0, 1e0u"GeV", 1e12u"GeV")
        Random.seed!(9999)
        samples_wide = rand(pl_wide, 1000)
        @test all(pl_wide.emin .<= samples_wide .<= pl_wide.emax)

        # gamma = 1 (logarithmic distribution)
        pl_log = UnitfulPowerLawSampler(1.0, 1e3u"GeV", 1e6u"GeV")
        Random.seed!(9999)
        samples_log = rand(pl_log, 1000)
        @test all(pl_log.emin .<= samples_log .<= pl_log.emax)

        # Steep spectrum (gamma = 3)
        pl_steep = UnitfulPowerLawSampler(3.0, 1e3u"GeV", 1e6u"GeV")
        Random.seed!(9999)
        samples_steep = rand(pl_steep, 1000)
        @test all(pl_steep.emin .<= samples_steep .<= pl_steep.emax)

        # Steeper spectrum should have lower mean energy than gamma=2
        mean_steep = mean(log10.(ustrip.(samples_steep)))
        Random.seed!(9999)
        pl_normal = UnitfulPowerLawSampler(2.0, 1e3u"GeV", 1e6u"GeV")
        samples_normal = rand(pl_normal, 1000)
        mean_normal = mean(log10.(ustrip.(samples_normal)))
        @test mean_steep < mean_normal
    end

    @testset "Probability Calculations" begin
        pl = UnitfulPowerLawSampler(2.0, 1e3u"GeV", 1e6u"GeV")

        # PDF should be higher at lower energies for gamma > 1
        pdf_low  = pl(2e3u"GeV")
        pdf_high = pl(5e5u"GeV")
        @test pdf_low > pdf_high

        # Rough normalization check via log-space integration
        n_points  = 1000
        e_values  = 10 .^ range(log10(1e3), log10(1e6), length=n_points) .* u"GeV"
        pdf_vals  = [ustrip(pl(e)) for e in e_values]
        de        = diff(log10.(ustrip.(e_values)))
        integral  = sum(pdf_vals[1:end-1] .* ustrip.(e_values[1:end-1]) .* de .* log(10))
        @test isapprox(integral, 1.0, rtol=0.1)

        # Angular probability for full sky
        as   = UniformAngularSampler(0.0, π, 0.0, 2π)
        prob = probability(as, π/4, π)
        @test isapprox(prob, 1/(4π), rtol=0.01)
    end

    @testset "Reproducibility" begin
        pl = UnitfulPowerLawSampler(2.0, 1e5u"GeV", 1e8u"GeV")
        as = UniformAngularSampler(0.0, π/2, 0.0, 2π)

        Random.seed!(777)
        seq1_energy = [rand(pl) for _ in 1:100]
        seq1_angles = [rand(as) for _ in 1:100]

        Random.seed!(777)
        seq2_energy = [rand(pl) for _ in 1:100]
        seq2_angles = [rand(as) for _ in 1:100]

        @test all(seq1_energy .== seq2_energy)
        @test all(seq1_angles .== seq2_angles)

        Random.seed!(778)
        seq3_energy = [rand(pl) for _ in 1:100]
        @test any(seq1_energy .!= seq3_energy)
    end
end

# ============================================================================
# Individual event tests
# ============================================================================

function test_powerlaw_single_event()
    Random.seed!(12345)
    pl = UnitfulPowerLawSampler(2.0, 1e5u"GeV", 1e9u"GeV")
    e1 = rand(pl)
    @test ustrip(e1) > 0
    @test pl.emin <= e1 <= pl.emax

    Random.seed!(12345)
    e_expected = rand(pl)
    Random.seed!(12345)
    e_actual = rand(pl)
    @test e_actual == e_expected

    Random.seed!(42)
    samples1 = rand(pl, 5)
    Random.seed!(42)
    samples2 = rand(pl, 5)
    @test all(samples1 .== samples2)
end

function test_angular_sampler_single_event()
    Random.seed!(54321)
    as = UniformAngularSampler(0.0, π, 0.0, 2π)
    θ1, ϕ1 = rand(as)
    @test 0 <= θ1 <= π
    @test 0 <= ϕ1 <= 2π

    Random.seed!(54321)
    θ2, ϕ2 = rand(as)
    @test θ1 == θ2
    @test ϕ1 == ϕ2

    as_restricted = UniformAngularSampler(0.0, π/2, π/4, 3π/4)
    Random.seed!(99999)
    θ3, ϕ3 = rand(as_restricted)
    @test 0 <= θ3 <= π/2
    @test π/4 <= ϕ3 <= 3π/4
end

function test_coordinate_conversions()
    θ_original = π/4
    ϕ_original = π/3
    cart = sph_to_cart(θ_original, ϕ_original)
    @test length(cart) == 3
    @test isapprox(norm(cart), 1.0, atol=1e-10)

    θ_back, ϕ_back = cart_to_sph(Direction(cart, ecefcoordinates))
    @test isapprox(θ_original, θ_back, atol=1e-10)
    @test isapprox(ϕ_original, ϕ_back, atol=1e-10)

    @test isapprox(sph_to_cart(0.0, 0.0)[3],  1.0, atol=1e-10)
    @test isapprox(sph_to_cart(π,   0.0)[3], -1.0, atol=1e-10)
end

function test_particle_creation()
    cs  = ecefcoordinates
    pos = Coordinate([1000.0u"m", 2000.0u"m", 3000.0u"m"], cs)
    dir = Direction([0.0, 0.0, 1.0], cs)

    p1 = Particle(TauMinus, 1e6u"GeV", pos, dir)
    @test p1.pdg == TauMinus
    @test p1.energy == 1e6u"GeV"
    @test p1.position == pos
    @test p1.direction == dir

    p2 = Particle(TauMinus, 1e6u"GeV", pos, dir)
    @test p1.pdg == p2.pdg
    @test p1.energy == p2.energy
    @test p1.position.point == p2.position.point
    @test p1.direction.point == p2.direction.point
end

# ============================================================================
# Distribution moment tests
# ============================================================================

function test_powerlaw_distribution_moments()
    n_samples = 100_000
    Random.seed!(2024)

    pl = UnitfulPowerLawSampler(2.0, 1e3u"GeV", 1e6u"GeV")
    samples = rand(pl, n_samples)
    log_samples = log10.(ustrip.(samples))

    mean_log_e = mean(log_samples)
    std_log_e  = std(log_samples)

    @test 3.0 < mean_log_e < 6.0
    @test mean_log_e < 4.5        # weighted toward lower energies for gamma > 1
    @test 0.3 < std_log_e < 1.5

    pl_flat = UnitfulPowerLawSampler(1.5, 1e3u"GeV", 1e6u"GeV")
    Random.seed!(2024)
    samples_flat  = rand(pl_flat, n_samples)
    mean_log_flat = mean(log10.(ustrip.(samples_flat)))
    @test mean_log_flat > mean_log_e  # flatter spectrum → higher mean energy
end

function test_angular_distribution_moments()
    n_samples = 50_000
    Random.seed!(2025)

    as = UniformAngularSampler(0.0, π, 0.0, 2π)
    samples    = [rand(as) for _ in 1:n_samples]
    cos_thetas = cos.([s[1] for s in samples])
    @test isapprox(mean(cos_thetas), 0.0, atol=0.02)
    @test isapprox(mean([s[2] for s in samples]), π, atol=0.05)

    as_upper = UniformAngularSampler(0.0, π/2, 0.0, 2π)
    Random.seed!(2025)
    samples_upper = [rand(as_upper) for _ in 1:n_samples]
    @test isapprox(mean(cos.([s[1] for s in samples_upper])), 0.5, atol=0.02)
end

function test_combined_sampling_moments()
    n_samples = 10_000
    Random.seed!(2026)

    pl = UnitfulPowerLawSampler(2.0, 1e5u"GeV", 1e8u"GeV")
    as = UniformAngularSampler(0.0, π/2, 0.0, 2π)
    cs = ecefcoordinates

    particles = Particle{Float64}[]
    for _ in 1:n_samples
        energy = rand(pl)
        dir    = rand(as, cs)
        pos    = Coordinate([0.0u"m", 0.0u"m", 6.4e6u"m"], cs)
        push!(particles, Particle(NuTau, energy, pos, dir))
    end

    energies    = [ustrip(p.energy) for p in particles]
    mean_log_e  = mean(log10.(energies))
    @test 5.0 < mean_log_e < 8.0

    # All directions should lie in the upper hemisphere
    thetas = [cart_to_sph(p.direction)[1] for p in particles]
    @test all(0 .<= thetas .<= π/2 + 0.01)

    @test all(p.pdg == NuTau for p in particles)
end
