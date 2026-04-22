"""
Tests for the downgoing proton injection functionality.

Covers:
- inject_proton_event: verifies proton starts at ~50 km altitude, correct PDG, energy in range
- inject_protons!: verifies frames get injection_initial_state key
"""

import Tambo: CoordinateSystem, precompute_detector_properties,
              inject_proton_event, PPlus, load_earth!

using Unitful

function make_test_gframe()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    earth_path = joinpath(tambosim_path, "resources", "geometry", "colca_valley.h5") * ":colca_valley_30000"
    gframe = Frame('G')
    gframe["earth_path"]   = earth_path
    gframe["detector_key"] = "detector1"
    load_earth!(gframe)
    return gframe
end

function run_proton_injection_tests()
    @testset "inject_proton_event" begin
        test_proton_altitude()
        test_proton_particle_type()
        test_proton_energy_in_range()
        test_proton_returns_visible_areas()
    end

    @testset "inject_protons!" begin
        test_inject_protons_produces_frames()
    end
end

# ============================================================================
# inject_proton_event tests
# ============================================================================

function test_proton_altitude()
    gframe = make_test_gframe()
    bvh = gframe["bvh"]; cs = gframe["cs"]
    topography = gframe["topography"]; detector_region = gframe["detector_region"]

    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    # Downgoing: theta in [91, 130] deg to ensure visibility of downward-facing detector triangles
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    altitude = 50.0u"km"

    # Try up to 100 times to get a successful injection
    final_proton = nothing
    for _ in 1:100
        _, fp, _, _ = inject_proton_event(bvh, cs, detector_region, as, pl, detector_props; altitude=altitude)
        if !isnan(fp.energy)
            final_proton = fp
            break
        end
    end

    @test !isnothing(final_proton)

    if !isnothing(final_proton)
        # z-coordinate in local (ENU) frame should be near 50 km.
        # For off-nadir directions at an elevated site (Colca Valley ~3-4 km),
        # ENU z diverges from geodetic altitude, so allow a generous tolerance.
        z_m = ustrip(u"m", final_proton.position.point[3])
        @test isapprox(z_m, 50_000.0, atol=5000.0)
    end
end

function test_proton_particle_type()
    gframe = make_test_gframe()
    bvh = gframe["bvh"]; cs = gframe["cs"]
    topography = gframe["topography"]; detector_region = gframe["detector_region"]
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, _, _ = inject_proton_event(bvh, cs, detector_region, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.pdg == PPlus
            return
        end
    end
    @test false
end

function test_proton_energy_in_range()
    gframe = make_test_gframe()
    bvh = gframe["bvh"]; cs = gframe["cs"]
    topography = gframe["topography"]; detector_region = gframe["detector_region"]
    emin, emax = 1e3u"GeV", 1e7u"GeV"
    pl = UnitfulPowerLawSampler(2.7, emin, emax)
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, _, _ = inject_proton_event(bvh, cs, detector_region, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.energy >= emin
            @test p.energy <= emax
            return
        end
    end
    @test false
end

function test_proton_returns_visible_areas()
    gframe = make_test_gframe()
    bvh = gframe["bvh"]; cs = gframe["cs"]
    topography = gframe["topography"]; detector_region = gframe["detector_region"]
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(topography, detector_region)

    for _ in 1:100
        p, _, va, _ = inject_proton_event(bvh, cs, detector_region, as, pl, detector_props)
        if !isnan(p.energy)
            @test !isnothing(va)
            @test length(va) == length(detector_props.triangles)
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

    config = Dict{String,Any}(
        "geometry" => Dict{String,Any}(
            "earth_path" => joinpath(tambosim_path, "resources", "geometry", "colca_valley.h5") * ":colca_valley_30000",
            "detector_key" => "detector1"
        ),
        "injection" => Dict{String,Any}(
            "pinecone"  => 42,
            "nevent"    => 20,
            "gamma"     => 2.7,
            "emin"      => 1e3,
            "emax"      => 1e7,
            "thetamin"  => 91.0,
            "thetamax"  => 130.0,
            "phimin"    => 0.0,
            "phimax"    => 360.0,
            "altitude"  => 50.0
        )
    )
    frames = Tambo.load_config(config)

    inject_protons!(frames)

    q_frames = filter(f -> f.stream == 'Q', frames)
    @test length(q_frames) == 20

    n_primary = count(f -> haskey(f, "injection_initial_state"), q_frames)
    @test n_primary > 0

    cut_frames!(frames, f -> haskey(f, "injection_initial_state"))
    q_frames = filter(f -> f.stream == 'Q', frames)
    @test all(f -> haskey(f, "injection_initial_state"), q_frames)
    @test all(f -> haskey(f, "injection_final_state"), q_frames)
end
