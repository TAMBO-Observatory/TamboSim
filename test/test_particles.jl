include("testsetup.jl")
"""
Tests for the particles module including particle types and particle state.

These tests use the actual TamboSim types from src/ to ensure code coverage.
"""

# Import particle-related types and functions
import TamboSim: ParticleType, Unknown, Gamma, EPlus, EMinus, MuPlus, MuMinus,
              TauPlus, TauMinus, NuTau, NuTauBar,
              FitStatus, NotSet, OK, GeneralFailure,
              ParticleShape, Null,
              particle_vacuum_range, particle_rock_range, gamma as gamma_factor,
              particle_parameters, range_parameters

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

    @testset "Null Constructors" begin
        test_particle_null_with_id()
    end

    @testset "Particle Physics (extra)" begin
        test_particle_mass_lookup()
        test_particle_speed_from_pdg()
        test_particle_speed_massless()
        test_lorentz_gamma()
        test_particle_vacuum_range_from_particle()
    end

    @testset "StochasticLoss" begin
        test_stochastic_loss_construction()
    end
end

function test_particle_types()
    @test Int(TauMinus) == 15
    @test Int(TauPlus) == -15
    @test Int(MuMinus) == 13
    @test Int(MuPlus) == -13
    @test Int(EMinus) == 11
    @test Int(EPlus) == -11
    @test Int(NuTau) == 16
    @test Int(NuTauBar) == -16
    @test Int(Unknown) == 0
end

function test_fit_status()
    @test Int(NotSet) == -1
    @test Int(OK) == 0
    @test Int(GeneralFailure) == 10
end

function test_particle_shape()
    @test Int(Null) == 0
end

function test_particle_default_construction()
    p = Particle(Float64)

    @test p.id == 0
    @test p.pdg == Unknown
    @test isnan(ustrip(p.energy))
    @test p.status == NotSet
    @test p.shape == Null
end

function test_particle_full_construction()
    cs = ecefcoordinates
    pos = Coordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)
    dir = Direction([0.0, 0.0, 1.0], cs)
    energy = 100.0u"GeV"

    p = Particle(TauMinus, energy, pos, dir)

    @test p.pdg == TauMinus
    @test p.energy == 100.0u"GeV"
    @test p.position == pos
    @test p.direction == dir
    @test p.id == 0
end

function test_particle_with_pdg()
    cs = ecefcoordinates
    pos = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    dir = Direction([1.0, 0.0, 0.0], cs)
    energy = 1.0u"TeV"

    p_tau = Particle(TauMinus, energy, pos, dir)
    @test p_tau.pdg == TauMinus

    p_mu = Particle(MuMinus, energy, pos, dir)
    @test p_mu.pdg == MuMinus

    p_e = Particle(EMinus, energy, pos, dir)
    @test p_e.pdg == EMinus
end

function test_gamma_factor_calc()
    ke = 10.0u"GeV"
    m = 0.1057u"GeV" / speedoflight^2  # muon mass

    g = gamma_factor(ke, m)

    # gamma = E / (m*c^2), so ~10 GeV / 0.1057 GeV ≈ 94.6
    @test g > 90
    @test g < 100
end

function test_vacuum_range()
    pdg = TauMinus
    energy = 1000.0u"GeV"
    epsilon = 1e-3

    range = particle_vacuum_range(pdg, energy, epsilon)

    @test range > 0u"m"
    @test unit(range) == u"m"

    # Higher energy should give longer range
    range_high = particle_vacuum_range(pdg, 10000.0u"GeV", epsilon)
    @test range_high > range
end

function test_rock_range()
    energy = 1000.0u"GeV"

    # Test muon rock range
    range_mu = particle_rock_range(energy, MuMinus)
    @test !isnan(ustrip(range_mu))
    @test ustrip(range_mu) > 0

    # Test tau rock range
    range_tau = particle_rock_range(energy, TauMinus)
    @test !isnan(ustrip(range_tau))
    @test ustrip(range_tau) > 0

    # Higher energy should give longer range
    range_high = particle_rock_range(10000.0u"GeV", MuMinus)
    @test ustrip(range_high) > ustrip(range_mu)
end

function test_particle_to_ray()
    cs = ecefcoordinates
    pos = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    dir = Direction([0.0, 0.0, 1.0], cs)
    p   = Particle(TauMinus, 100.0u"GeV", pos, dir)
    ray = Ray(p)
    @test ray.origin == p.position
    @test ray.direction == p.direction
end

function test_particle_null_with_id()
    p = Particle(42, Float64)
    @test p.id == 42
    @test p.pdg == TamboSim.Unknown
    @test isnan(ustrip(p.energy))
end

function test_particle_mass_lookup()
    m = particle_mass(TauMinus)
    @test ustrip(m) > 0
end

function test_particle_speed_from_pdg()
    v = particle_speed(1e5u"GeV", TauMinus)
    c = 299_792_458.0u"m/s"
    @test ustrip(u"m/s", v) > 0
    @test ustrip(u"m/s", v) <= ustrip(u"m/s", c)
end

function test_particle_speed_massless()
    v = particle_speed(1.0u"GeV", 0.0u"GeV" / speedoflight^2)
    @test isapprox(ustrip(u"m/s", v), 299_792_458.0, rtol=1e-6)
end

function test_lorentz_gamma()
    γ = lorentz_gamma(1e5u"GeV", 1.77686u"GeV" / speedoflight^2)
    @test γ > 1.0
end

function test_particle_vacuum_range_from_particle()
    cs = ecefcoordinates
    p  = Particle(TauMinus, 1e5u"GeV",
                  Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
                  Direction([0.0, 0.0, 1.0], cs))
    r = particle_vacuum_range(p, 0.5)
    @test ustrip(u"m", r) > 0
end

function test_stochastic_loss_construction()
    cs  = ecefcoordinates
    pos = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)

    loss = StochasticLoss(1, 100.0u"GeV", pos)
    @test loss.int_type == 1
    @test loss.energy == 100.0u"GeV"
    @test loss.position == pos

    # Unit conversion: 1000 MeV == 1 GeV
    @test StochasticLoss(1, 1000.0u"MeV", pos).energy == 1.0u"GeV"
    @test StochasticLoss(1, 0.001u"TeV", pos).energy  == 1.0u"GeV"
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Particles" begin
        run_particle_tests()
    end
end
