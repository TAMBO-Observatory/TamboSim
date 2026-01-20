"""
Tests for the particles module including particle types and particle state.
"""

# ============================================================================
# Particle types for testing
# ============================================================================

@enum TestParticleType begin
    TestUnknown = 0
    TestGamma = 22
    TestEPlus = -11
    TestEMinus = 11
    TestMuPlus = -13
    TestMuMinus = 13
    TestTauPlus = -15
    TestTauMinus = 15
    TestNuTau = 16
    TestNuTauBar = -16
end

@enum TestFitStatus begin
    TestNotSet = -1
    TestOK = 0
    TestGeneralFailure = 10
end

@enum TestParticleShape begin
    TestNull = 0
end

# ============================================================================
# Particle struct for testing
# ============================================================================

struct TestParticle{T<:Real}
    id::Int
    pdg::TestParticleType
    energy::Quantity{T, edim, typeof(u"GeV")}
    position::TestCoordinate{T}
    direction::TestDirection{T}
    time::Quantity{T, tdim, typeof(u"s")}
    status::TestFitStatus
    shape::TestParticleShape
    speed::Quantity{T, ldim/tdim, typeof(u"m/s")}
end

function TestParticle(::Type{T}) where {T}
    cs = test_ecef
    return TestParticle{T}(
        0,
        TestUnknown,
        NaN * u"GeV",
        TestCoordinate([NaN * u"m", NaN * u"m", NaN * u"m"], cs),
        TestDirection([0.0, 0.0, -1.0], cs),
        NaN * u"s",
        TestNotSet,
        TestNull,
        NaN * u"m/s"
    )
end

function TestParticle(pdg::TestParticleType, e, pos::TestCoordinate{T}, dir::TestDirection{T}) where {T}
    return TestParticle{T}(
        0, pdg, e |> u"GeV", pos, dir, 0.0u"s", TestNotSet, TestNull, 0.0u"m/s"
    )
end

# Physics functions
const test_particle_params = Dict(
    TestTauMinus => (1.77686u"GeV" / speedoflight^2, 2.903e-13u"s"),
    TestTauPlus => (1.77686u"GeV" / speedoflight^2, 2.903e-13u"s"),
    TestMuMinus => (0.1056583745u"GeV" / speedoflight^2, 2.1969811e-6u"s"),
    TestMuPlus => (0.1056583745u"GeV" / speedoflight^2, 2.1969811e-6u"s"),
    TestEMinus => (0.00051099895000u"GeV" / speedoflight^2, Inf * u"s"),
    TestEPlus => (0.00051099895000u"GeV" / speedoflight^2, Inf * u"s"),
)

const test_range_params = Dict(
    TestMuMinus => (1.76666667e-1u"GeV*cm^3/m/g", 2.0916666667e-4u"cm^3/m/g"),
    TestMuPlus => (1.76666667e-1u"GeV*cm^3/m/g", 2.0916666667e-4u"cm^3/m/g"),
    TestTauMinus => (1.473684210526e3u"GeV*cm^3/m/g", 2.63e-5u"cm^3/m/g"),
    TestTauPlus => (1.473684210526e3u"GeV*cm^3/m/g", 2.63e-5u"cm^3/m/g"),
)

function test_gamma_factor(ke, m)
    return ustrip(ke / m / speedoflight^2)
end

function test_particle_vacuum_range(pdg::TestParticleType, energy, epsilon=1e-3)
    m, tau = test_particle_params[pdg]
    γ = test_gamma_factor(energy, m)
    return -γ * speedoflight * tau * log(epsilon)
end

function test_particle_rock_range(e, pdg::TestParticleType)
    α, β = test_range_params[pdg]
    range = log(1 + e * β / α) / β
    return range
end

# ============================================================================
# Test functions
# ============================================================================

function run_particle_tests()
    @testset "Particle Types" begin
        test_particle_types()
        test_fit_status()
        test_particle_shape()
    end

    @testset "Particle Construction" begin
        test_particle_default_construction()
        test_particle_full_construction()
        test_particle_with_pdg()
    end

    @testset "Particle Physics" begin
        test_gamma_factor_calc()
        test_vacuum_range()
        test_rock_range()
    end

    @testset "Particle to Ray" begin
        test_particle_to_ray()
    end
end

function test_particle_types()
    @test Int(TestTauMinus) == 15
    @test Int(TestTauPlus) == -15
    @test Int(TestMuMinus) == 13
    @test Int(TestMuPlus) == -13
    @test Int(TestEMinus) == 11
    @test Int(TestEPlus) == -11
    @test Int(TestNuTau) == 16
    @test Int(TestNuTauBar) == -16
    @test Int(TestUnknown) == 0
end

function test_fit_status()
    @test Int(TestNotSet) == -1
    @test Int(TestOK) == 0
    @test Int(TestGeneralFailure) == 10
end

function test_particle_shape()
    @test Int(TestNull) == 0
end

function test_particle_default_construction()
    p = TestParticle(Float64)

    @test p.id == 0
    @test p.pdg == TestUnknown
    @test isnan(ustrip(p.energy))
    @test p.status == TestNotSet
    @test p.shape == TestNull
end

function test_particle_full_construction()
    cs = test_ecef
    pos = TestCoordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)
    dir = TestDirection([0.0, 0.0, 1.0], cs)
    energy = 100.0u"GeV"

    p = TestParticle(TestTauMinus, energy, pos, dir)

    @test p.pdg == TestTauMinus
    @test p.energy == 100.0u"GeV"
    @test p.position == pos
    @test p.direction == dir
    @test p.id == 0
end

function test_particle_with_pdg()
    cs = test_ecef
    pos = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    dir = TestDirection([1.0, 0.0, 0.0], cs)
    energy = 1.0u"TeV"

    p_tau = TestParticle(TestTauMinus, energy, pos, dir)
    @test p_tau.pdg == TestTauMinus

    p_mu = TestParticle(TestMuMinus, energy, pos, dir)
    @test p_mu.pdg == TestMuMinus

    p_e = TestParticle(TestEMinus, energy, pos, dir)
    @test p_e.pdg == TestEMinus
end

function test_gamma_factor_calc()
    ke = 10.0u"GeV"
    m = 0.1057u"GeV" / speedoflight^2  # muon mass

    g = test_gamma_factor(ke, m)

    # gamma = E / (m*c^2), so ~10 GeV / 0.1057 GeV ≈ 94.6
    @test g > 90
    @test g < 100
end

function test_vacuum_range()
    pdg = TestTauMinus
    energy = 1000.0u"GeV"
    epsilon = 1e-3

    range = test_particle_vacuum_range(pdg, energy, epsilon)

    @test range > 0u"m"
    @test unit(range) == u"m"

    # Higher energy should give longer range
    range_high = test_particle_vacuum_range(pdg, 10000.0u"GeV", epsilon)
    @test range_high > range
end

function test_rock_range()
    energy = 100.0u"GeV"
    pdg = TestMuMinus

    range = test_particle_rock_range(energy, pdg)

    # Range has units of m*g/cm^3 (mass per area times length)
    @test range > 0u"m*g/cm^3"

    # Higher energy should give longer range
    range_high = test_particle_rock_range(1000.0u"GeV", pdg)
    @test range_high > range
end

function test_particle_to_ray()
    cs = test_ecef
    pos = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    dir = TestDirection([0.0, 0.0, 1.0], cs)
    energy = 100.0u"GeV"

    p = TestParticle(TestTauMinus, energy, pos, dir)
    ray = TestRay(p.position, p.direction)

    @test ray.origin == p.position
    @test ray.direction == p.direction
end
