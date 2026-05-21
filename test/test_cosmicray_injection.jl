include("testsetup.jl")
"""
Tests for the downgoing cosmic-ray injection functionality.

Covers:
- inject_cosmicray_event: verifies the primary starts at ~target altitude,
  honors the requested pdg (proton and nucleus), energy in range
- inject_cosmicrays!: verifies frames get injection_initial_state key
"""

import TamboSim: CoordinateSystem, precompute_detector_properties,
              inject_cosmicray_event, nucleus_pdg, PPlus, O16Nucleus, Fe56Nucleus

using Unitful

function make_test_frames()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    geometry_path = joinpath(tambosim_path, "resources", "geometry", "colca_valley_3000.jld2")
    return load_frames(geometry_path)
end

function run_cosmicray_injection_tests()
    @testset "inject_cosmicray_event" begin
        test_cosmicray_altitude()
        test_cosmicray_particle_type()
        test_cosmicray_energy_in_range()
        test_cosmicray_returns_phase_space_point()
    end

    @testset "inject_cosmicrays!" begin
        test_inject_cosmicrays_produces_frames()
    end

    @testset "nucleus_pdg & pdg resolution" begin
        test_nucleus_pdg()
        test_resolve_primary_pdg()
        test_inject_cosmicrays_AZ_config()
    end
end

# ============================================================================
# inject_cosmicray_event tests
# ============================================================================

function test_cosmicray_altitude()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]

    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    # Downgoing: theta in [91, 130] deg to ensure visibility of downward-facing detector triangles
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    altitude = 50.0u"km"

    # Try up to 100 times to get a successful injection
    final_primary = nothing
    for _ in 1:100
        _, fp, _ = inject_cosmicray_event(2212, cs, as, pl, detector_props; altitude=altitude)
        if !isnan(fp.energy)
            final_primary = fp
            break
        end
    end

    @test !isnothing(final_primary)

    if !isnothing(final_primary)
        # Check geodetic altitude via ECEF radial distance minus Earth radius at the detector.
        # ENU z is not a valid proxy: for off-nadir directions the injection point can be
        # thousands of km from the detector horizontally, so ENU z << geodetic altitude.
        ecef_pos = convert(ecefcoordinates, final_primary.position)
        r_m = ustrip(u"m", norm(ecef_pos.point))
        rearth_m = ustrip(u"m", norm(g_frame["cs"].origin))
        altitude_m = r_m - rearth_m
        @test isapprox(altitude_m, 50_000.0, atol=1000.0)
    end
end

function test_cosmicray_particle_type()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    # Proton pdg → PPlus
    proton_ok = false
    for _ in 1:100
        p, _, _ = inject_cosmicray_event(2212, cs, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.pdg == PPlus
            proton_ok = true
            break
        end
    end
    @test proton_ok

    # Nucleus pdg (O-16, 1000080160) → O16Nucleus — verifies config pdg is honored
    nucleus_ok = false
    for _ in 1:100
        p, _, _ = inject_cosmicray_event(1000080160, cs, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.pdg == O16Nucleus
            nucleus_ok = true
            break
        end
    end
    @test nucleus_ok
end

function test_cosmicray_energy_in_range()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]
    emin, emax = 1e3u"GeV", 1e7u"GeV"
    pl = UnitfulPowerLawSampler(2.7, emin, emax)
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, _ = inject_cosmicray_event(2212, cs, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.energy >= emin
            @test p.energy <= emax
            return
        end
    end
    @test false
end

function test_cosmicray_returns_phase_space_point()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, point = inject_cosmicray_event(2212, cs, as, pl, detector_props)
        if !isnan(p.energy)
            @test point isa SurfaceCRPoint
            @test point.E == p.energy
            @test point.area > 0.0u"m^2"
            return
        end
    end
    @test false
end

# ============================================================================
# inject_cosmicrays! tests
# ============================================================================

function test_inject_cosmicrays_produces_frames()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))

    geometry_path = joinpath(tambosim_path, "resources", "geometry", "colca_valley_3000.jld2")
    injection_config = Dict{String,Any}(
        "strategy"  => "CosmicRayInjection",
        "seed"  => 42,
        "nevent"    => 20,
        "pdg"       => 2212,
        "gamma"     => 2.7,
        "emin"      => 1e3,
        "emax"      => 1e7,
        "thetamin"  => 91.0,
        "thetamax"  => 130.0,
        "phimin"    => 0.0,
        "phimax"    => 360.0,
        "altitude"  => 50.0
    )
    frames = load_frames(geometry_path)

    TamboSim.inject_cosmicrays!(frames, injection_config)

    q_frames = filter(f -> f.stream == 'Q', frames)
    @test length(q_frames) == 20

    n_primary = count(f -> haskey(f, "injection_initial_state"), q_frames)
    @test n_primary > 0

    filter!(f -> haskey(f, "injection_initial_state"), frames)
    q_frames = filter(f -> f.stream == 'Q', frames)
    @test all(f -> haskey(f, "injection_initial_state"), q_frames)
end

# ============================================================================
# nucleus_pdg + pdg-resolution tests
# ============================================================================

function test_nucleus_pdg()
    @test nucleus_pdg(16, 8)  == 1000080160
    @test nucleus_pdg(16, 8)  == Int(O16Nucleus)
    @test nucleus_pdg(56, 26) == 1000260560
    @test nucleus_pdg(56, 26) == Int(Fe56Nucleus)
    # A=1, Z=1 should warn and return 2212 (PPlus)
    @test (@test_warn r"free proton" nucleus_pdg(1, 1)) == 2212
    # bounds checks
    @test_throws ErrorException nucleus_pdg(8, 0)    # Z < 1
    @test_throws ErrorException nucleus_pdg(4, 6)    # A < Z
    @test_throws ErrorException nucleus_pdg(300, 119) # Z > 118
end

function test_resolve_primary_pdg()
    rp = TamboSim._resolve_primary_pdg
    @test rp(Dict{String,Any}("pdg" => 2212)) == 2212
    @test rp(Dict{String,Any}("A" => 16, "Z" => 8)) == 1000080160
    # Ambiguous (both forms), missing (neither), and partial (one of A/Z) all error
    @test_throws ErrorException rp(Dict{String,Any}("pdg" => 2212, "A" => 1, "Z" => 1))
    @test_throws ErrorException rp(Dict{String,Any}())
    @test_throws ErrorException rp(Dict{String,Any}("A" => 16))
end

function test_inject_cosmicrays_AZ_config()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    geometry_path = joinpath(tambosim_path, "resources", "geometry", "colca_valley_3000.jld2")
    # O-16 nucleus specified via A/Z, no explicit pdg
    injection_config = Dict{String,Any}(
        "strategy" => "CosmicRayInjection",
        "seed"     => 42,
        "nevent"   => 10,
        "A"        => 16,
        "Z"        => 8,
        "gamma"    => 2.7,
        "emin"     => 1e3,
        "emax"     => 1e7,
        "thetamin" => 91.0,
        "thetamax" => 130.0,
        "phimin"   => 0.0,
        "phimax"   => 360.0,
        "altitude" => 50.0,
    )
    frames = load_frames(geometry_path)
    TamboSim.inject_cosmicrays!(frames, injection_config)

    # The resolved pdg must be canonicalized onto the M-frame snapshot so
    # downstream weighting works even though the config used A/Z.
    m = frames.m_frames[end]
    @test m["injection"]["pdg"] == 1000080160

    ps = TamboSim.build_phase_space(m)
    @test ps isa CosmicRayInjectionPS
    @test ps.pdg == 1000080160
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Cosmic Ray Injection" begin
        run_cosmicray_injection_tests()
    end
end
