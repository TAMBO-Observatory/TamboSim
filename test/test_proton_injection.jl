"""
Tests for the downgoing proton injection functionality.

Covers:
- inject_proton_event: verifies proton starts at ~50 km altitude, correct PDG, energy in range
- inject_protons!: verifies frames get injection_initial_state key
"""

import Tambo: CoordinateSystem, precompute_detector_properties,
              inject_proton_event, PPlus

using Unitful

function make_test_earth()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    earth_path = joinpath(tambosim_path, "resources", "geometry", "colca_valley.h5") * ":colca_valley_30000"
    Tambo.Earth(earth_path, "detector1")
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

    @testset "single particle type guard" begin
        test_inject_protons_rejects_nonempty_sim()
        test_inject_rejects_nonempty_sim()
    end
end

# ============================================================================
# inject_proton_event tests
# ============================================================================

function test_proton_altitude()
    earth = make_test_earth()

    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    # Downgoing: theta in [91, 130] deg to ensure visibility of downward-facing detector triangles
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(earth)

    altitude = 50.0u"km"

    # Try up to 100 times to get a successful injection
    final_proton = nothing
    for _ in 1:100
        _, fp, _, _ = inject_proton_event(earth, as, pl, detector_props; altitude=altitude)
        if !isnan(fp.energy)
            final_proton = fp
            break
        end
    end

    @test !isnothing(final_proton)

    if !isnothing(final_proton)
        # z-coordinate in local (ENU) frame should be ≈ 50 km = 50_000 m
        z_m = ustrip(u"m", final_proton.position.point[3])
        @test isapprox(z_m, 50_000.0, atol=1000.0)
    end
end

function test_proton_particle_type()
    earth = make_test_earth()
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(earth)

    for _ in 1:100
        p, _, _, _ = inject_proton_event(earth, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.pdg == PPlus
            return
        end
    end
    @test false
end

function test_proton_energy_in_range()
    earth = make_test_earth()
    emin, emax = 1e3u"GeV", 1e7u"GeV"
    pl = UnitfulPowerLawSampler(2.7, emin, emax)
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(earth)

    for _ in 1:100
        p, _, _, _ = inject_proton_event(earth, as, pl, detector_props)
        if !isnan(p.energy)
            @test p.energy >= emin
            @test p.energy <= emax
            return
        end
    end
    @test false
end

function test_proton_returns_visible_areas()
    earth = make_test_earth()
    pl = UnitfulPowerLawSampler(2.7, 1e3u"GeV", 1e7u"GeV")
    as = UniformAngularSampler(deg2rad(91.0), deg2rad(130.0), deg2rad(0.0), deg2rad(360.0))
    detector_props = precompute_detector_properties(earth)

    for _ in 1:100
        p, _, va, _ = inject_proton_event(earth, as, pl, detector_props)
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
    sim = Tambo.Simulation(config, Frame[])

    inject_protons!(sim)

    @test length(sim.results) == 20

    n_primary = count(f -> haskey(f, "injection_initial_state"), sim.results)
    @test n_primary > 0

    # After cut, all remaining frames should have both state keys
    cut_frames!(sim.results, f -> haskey(f, "injection_initial_state"))
    @test all(f -> haskey(f, "injection_initial_state"), sim.results)
    @test all(f -> haskey(f, "injection_final_state"), sim.results)
end

# ============================================================================
# Single particle type guard tests
# ============================================================================

function _make_proton_config()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    Dict{String,Any}(
        "geometry" => Dict{String,Any}(
            "earth_path" => joinpath(tambosim_path, "resources", "geometry", "colca_valley.h5") * ":colca_valley_30000",
            "detector_key" => "detector1"
        ),
        "injection" => Dict{String,Any}(
            "pinecone" => 42, "nevent" => 5,
            "gamma" => 2.7, "emin" => 1e3, "emax" => 1e7,
            "thetamin" => 91.0, "thetamax" => 130.0,
            "phimin" => 0.0, "phimax" => 360.0, "altitude" => 50.0
        )
    )
end

function test_inject_protons_rejects_nonempty_sim()
    # Pre-populate sim.results to simulate a prior injection
    config = _make_proton_config()
    sim = Tambo.Simulation(config, Frame[])
    push!(sim.results, Frame(Dict("event_id" => 1)))

    @test_throws ErrorException inject_protons!(sim)
end

function test_inject_rejects_nonempty_sim()
    tambosim_path = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
    config = Dict{String,Any}(
        "geometry" => Dict{String,Any}(
            "earth_path" => joinpath(tambosim_path, "resources", "geometry", "colca_valley.h5") * ":colca_valley_30000",
            "detector_key" => "detector1"
        ),
        "injection" => Dict{String,Any}(
            "pinecone" => 42, "nevent" => 5,
            "pdg" => 16, "gamma" => 1.5,
            "emin" => 3e5, "emax" => 1e7,
            "thetamin" => 0.0, "thetamax" => 117.0,
            "phimin" => 90.0, "phimax" => 290.0,
            "xs_location" => joinpath(tambosim_path, "resources", "cross_section_tables", "cross_sections.h5") * ":CSMS_nutau"
        )
    )
    sim = Tambo.Simulation(config, Frame[])
    push!(sim.results, Frame(Dict("event_id" => 1)))

    @test_throws ErrorException inject!(sim)
end
