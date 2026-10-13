include("testsetup.jl")
"""
Tests for Glashow-resonance injection (`src/injection/glashow.jl`): the ν̄_e e⁻ cross
sections, the τ energy sampler, and the committed GlashowInjection fixture.
"""

import TamboSim: GlashowCrossSection, glashow_sigma_total, glashow_sigma_tau,
                 glashow_dsigma_tau_dEtau, glashow_sigma_lepton_tree, sample_y_glashow,
                 GLASHOW_MW, GLASHOW_ME, GLASHOW_BR_LNU, GLASHOW_HBARC2,
                 ELECTRONS_PER_GRAM, ROCK_DENSITY, NuEBar, _get_last_frame

using HDF5

const _GLASHOW_GEOMETRY_PATH = joinpath(get_tambosim_path(), "resources", "geometry",
                                        "colca_valley_3000.jld2")
const _GLASHOW_OUTPUT_PATH = joinpath(get_tambosim_path(), "examples", "resources",
                                      "example_glashow_output.jld2")

const _E_RES = GLASHOW_MW^2 / (2 * GLASHOW_ME) * u"GeV"

# σ_τ/σ_tot = BR(W→ℓν) times the τ phase-space factor (1 − r)²(1 + r/2), r = m_τ²/s.
function _expected_tau_fraction(E)
    r = 1.77686^2 / (2 * GLASHOW_ME * ustrip(u"GeV", E))
    return GLASHOW_BR_LNU * (1 - r)^2 * (1 + r / 2)
end

function run_glashow_tests()
    @testset "Cross sections" begin
        test_glashow_peak()
        test_glashow_tau_branching()
        test_glashow_dsigma_integrates_to_sigma()
        test_glashow_absorption_length()
        test_glashow_below_tau_threshold()
    end
    @testset "Correction table" begin
        test_glashow_corrections_need_location()
        test_glashow_corrections_scale_tree_level()
    end
    @testset "τ energy sampler" begin
        test_glashow_y_sampler()
    end
    @testset "Fixture" begin
        test_glashow_fixture_states()
    end
end

function test_glashow_peak()
    xs = GlashowCrossSection()
    es = exp10.(range(6.7, 6.9, length=20001)) .* u"GeV"
    σ  = [ustrip(u"cm^2", glashow_sigma_total(xs, E)) for E in es]
    i  = argmax(σ)
    # Peak at s = M_W², i.e. E = M_W²/2m_e ≈ 6.32 PeV.
    @test ustrip(u"GeV", es[i]) ≈ ustrip(u"GeV", _E_RES) rtol=1e-3
    # σ_peak = 24π·BR(W→eν)/M_W² ≈ 4.95e-31 cm² (Gandhi et al. 1996: ~5.0e-31).
    peak = 24π * GLASHOW_BR_LNU / GLASHOW_MW^2 * GLASHOW_HBARC2
    @test σ[i] ≈ peak rtol=2e-3
    @test σ[i] ≈ 4.95e-31 rtol=0.02
end

function test_glashow_tau_branching()
    xs = GlashowCrossSection()
    for E in (1e6, _E_RES / u"GeV", 1e8) .* u"GeV"
        @test glashow_sigma_tau(xs, E) / glashow_sigma_total(xs, E) ≈ _expected_tau_fraction(E) rtol=1e-10
    end
    # Lepton universality vs the measured BR(W→τν) = 0.1138 ± 0.0021 (PDG).
    @test GLASHOW_BR_LNU ≈ 0.1138 rtol=0.06
end

function test_glashow_dsigma_integrates_to_sigma()
    xs = GlashowCrossSection()
    for E in (2e6, _E_RES / u"GeV", 5e7) .* u"GeV"
        ys = range(0, 1, length=20001)
        f  = [ustrip(u"cm^2/GeV", glashow_dsigma_tau_dEtau(xs, E, y * E)) for y in ys]
        integral = sum((f[1:end-1] .+ f[2:end]) ./ 2) * step(ys) * ustrip(u"GeV", E)
        @test integral ≈ ustrip(u"cm^2", glashow_sigma_tau(xs, E)) rtol=1e-6
    end
end

function test_glashow_absorption_length()
    xs = GlashowCrossSection()
    λ  = 1 / (ELECTRONS_PER_GRAM * ROCK_DENSITY * glashow_sigma_total(xs, _E_RES))
    # Ding & Liu quote λ_GR ≈ 26 km in standard rock at the peak.
    @test ustrip(u"km", λ) ≈ 26 rtol=0.05
end

function test_glashow_below_tau_threshold()
    # s < m_τ² has no τ channel: E < m_τ²/2m_e ≈ 3.1 TeV.
    @test glashow_sigma_lepton_tree(1e3u"GeV", 1.77686) == 0.0u"cm^2"
    @test glashow_sigma_lepton_tree(1e4u"GeV", 1.77686) > 0.0u"cm^2"
end

function test_glashow_corrections_need_location()
    @test_throws ErrorException GlashowCrossSection(; corrections=true)
end

function test_glashow_corrections_scale_tree_level()
    path = joinpath(mktempdir(), "gr.h5")
    es = exp10.(range(5, 9, length=401))
    h5open(path, "w") do f
        g = create_group(f, "GR_nuebar")
        g["energies"]    = es
        g["ratio_total"] = fill(0.8, length(es))
        g["ratio_tau"]   = fill(0.7, length(es))
    end
    tree = GlashowCrossSection()
    corr = GlashowCrossSection(; corrections=true, location="$(path):GR_nuebar")
    @test glashow_sigma_total(corr, _E_RES) ≈ 0.8 * glashow_sigma_total(tree, _E_RES)
    @test glashow_sigma_tau(corr, _E_RES)   ≈ 0.7 * glashow_sigma_tau(tree, _E_RES)
    @test_throws ArgumentError glashow_sigma_total(corr, 1e10u"GeV")
end

function test_glashow_y_sampler()
    Random.seed!(2026)
    n  = 200_000
    ys = [sample_y_glashow() for _ in 1:n]
    @test all(0 .<= ys .<= 1)
    edges  = range(0, 1, length=21)
    counts = fit(Histogram, ys, edges).weights
    # Expected bin probability: ∫ 3(1−y)² dy = (1−a)³ − (1−b)³.
    expected = [n * ((1 - a)^3 - (1 - b)^3) for (a, b) in zip(edges[1:end-1], edges[2:end])]
    mask = expected .> 50
    χ2 = sum((counts[mask] .- expected[mask]).^2 ./ expected[mask])
    @test χ2 < 50   # 19 dof (or fewer); p ≈ 1e-4 at 50
    @test mean(ys) ≈ 0.25 rtol=0.01
end

function test_glashow_fixture_states()
    frames = load_frames([_GLASHOW_GEOMETRY_PATH, _GLASHOW_OUTPUT_PATH])
    m = _get_last_frame(frames, 'M')
    @test m["injection"]["strategy"] == "GlashowInjection"
    @test m["injection"]["pdg"] == -12

    qs = frames.q_frames
    @test !isempty(qs)
    for q in qs
        istate = q["injection_initial_state"]
        fstate = q["injection_final_state"]
        pt     = q["phase_space_point"]
        @test istate.pdg == NuEBar
        @test fstate.pdg == TauMinus
        @test pt isa GlashowInteractionPoint
        @test pt.E == istate.energy
        @test pt.E_tau == fstate.energy
        @test 0u"GeV" < pt.E_tau <= pt.E
        @test pt.cd_cap > 0u"g/cm^2"
        @test pt.x_up >= 0u"g/cm^2"
        @test pt.sigma_tau / pt.sigma_gr ≈ _expected_tau_fraction(pt.E) rtol=1e-10
    end
    ows = oneweights(frames)
    @test all(ow -> isfinite(ustrip(ow)) && ustrip(ow) > 0, ows)
end
