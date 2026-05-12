include("testsetup.jl")
"""
Tests for the downgoing proton injection functionality.

Covers:
- inject_proton_event: verifies proton starts at ~50 km altitude, correct PDG, energy in range
- inject_protons!: verifies frames get injection_initial_state key
"""

import TamboSim: CoordinateSystem, precompute_detector_properties,
              inject_proton_event, PPlus

using Unitful

function make_test_frames()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    geometry_path = joinpath(tambosim_path, "resources", "geometry", "colca_valley_3000.jld2")
    return load_frames(geometry_path)
end

function run_proton_injection_tests()
    @testset "inject_proton_event" begin
        test_proton_altitude()
        test_proton_particle_type()
        test_proton_energy_in_range()
        test_proton_returns_phase_space_point()
    end

    @testset "inject_protons!" begin
        test_inject_protons_produces_frames()
    end
end

# ============================================================================
# inject_proton_event tests
# ============================================================================

function test_proton_altitude()
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
    final_proton = nothing
    for _ in 1:100
        _, fp, _ = inject_proton_event(cs, as, pl, detector_props; altitude=altitude)
        if !isnan(fp.energy)
            final_proton = fp
            break
        end
    end

    @test !isnothing(final_proton)

    if !isnothing(final_proton)
        # Check geodetic altitude via ECEF radial distance minus Earth radius at the detector.
        # ENU z is not a valid proxy: for off-nadir directions the injection point can be
        # thousands of km from the detector horizontally, so ENU z << geodetic altitude.
        ecef_pos = convert(ecefcoordinates, final_proton.position)
        r_m = ustrip(u"m", norm(ecef_pos.point))
        rearth_m = ustrip(u"m", norm(g_frame["cs"].origin))
        altitude_m = r_m - rearth_m
        @test isapprox(altitude_m, 50_000.0, atol=1000.0)
    end
end

function test_proton_particle_type()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, _ = inject_proton_event(cs, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.pdg == PPlus
            return
        end
    end
    @test false
end

function test_proton_energy_in_range()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]
    emin, emax = 1e3u"GeV", 1e7u"GeV"
    pl = UnitfulPowerLawSampler(2.7, emin, emax)
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, _ = inject_proton_event(cs, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.energy >= emin
            @test p.energy <= emax
            return
        end
    end
    @test false
end

function test_proton_returns_phase_space_point()
    frames = make_test_frames()
    g_frame = TamboSim._get_last_frame(frames, 'G'); d_frame = TamboSim._get_last_frame(frames, 'D')
    cs = g_frame["cs"]
    topography = g_frame["topography"]; detector_region = d_frame["detector_region"]
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, point = inject_proton_event(cs, as, pl, detector_props)
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
# inject_protons! tests
# ============================================================================

function test_inject_protons_produces_frames()
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

    TamboSim.inject_protons!(frames, injection_config)

    q_frames = filter(f -> f.stream == 'Q', frames)
    @test length(q_frames) == 20

    n_primary = count(f -> haskey(f, "injection_initial_state"), q_frames)
    @test n_primary > 0

    filter!(f -> haskey(f, "injection_initial_state"), frames)
    q_frames = filter(f -> f.stream == 'Q', frames)
    @test all(f -> haskey(f, "injection_initial_state"), q_frames)
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Proton Injection" begin
        run_proton_injection_tests()
    end
end
