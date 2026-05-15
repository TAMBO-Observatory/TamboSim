include("testsetup.jl")
"""
Tests for the top-level simulation API:
  - inject!            frame creation, parent wiring, config storage
  - proposal_propagation!  config storage, output keys written to Q frames
  - save_frames / load_frames  serialization roundtrip, multi-file load
  - relativize!        path resolution
"""

const GEOMETRY_PATH = joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                               "resources", "geometry", "colca_valley_3000.jld2")
const XS_PATH = joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                         "resources", "cross_section_tables",
                         "cross_sections.h5:CSMS_nutau")

function _injection_config(; nevent=10)
    Dict{String,Any}(
        "strategy"    => "NeutrinoInjection",
        "seed"    => 7,
        "nevent"      => nevent,
        "pdg"         => 16,
        "gamma"       => 2.0,
        "emin"        => 1e5,
        "emax"        => 1e8,
        "thetamin"    => 0.0,
        "thetamax"    => 117.0,
        "phimin"      => 90.0,
        "phimax"      => 290.0,
        "xs_location" => XS_PATH,
    )
end

function run_simulation_api_tests()
    @testset "inject!" begin
        test_inject_creates_c_and_q_frames()
        test_inject_config_stored_under_prefix()
        test_inject_q_frame_parents()
        test_inject_custom_prefix()
        test_inject_missing_nevent_errors()
        test_inject_missing_strategy_errors()
        test_inject_unknown_strategy_errors()
        test_inject_dispatches_to_protons()
    end

    @testset "neutrino initial_state position" begin
        test_initial_state_at_earth_entry()
    end

    @testset "proposal_propagation!" begin
        test_proposal_config_stored()
        test_proposal_output_keys()
        test_proposal_skips_below_rest_energy()
    end

    @testset "save_frames / load_frames" begin
        test_save_load_roundtrip()
        test_save_load_data_preserved()
        test_save_load_multi_file()
        test_save_geometry_self_contained()
    end

    @testset "relativize!" begin
        test_relativize_tambosim_path_placeholder()
        test_relativize_relative_path()
        test_relativize_absolute_path_untouched()
        test_relativize_non_path_string_untouched()
        test_relativize_nested_dict()
        test_relativize_non_string_value_untouched()
        test_relativize_tambo_data_path_placeholder()
        test_relativize_tambo_corsika_and_flupro_placeholders()
        test_relativize_env_placeholder_unset_yields_empty()
    end
end

# =============================================================================
# inject! tests
# =============================================================================

function test_inject_creates_c_and_q_frames()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=5))

    # GCD bundle contributes a blank C frame; inject! adds an M frame with config
    @test count(f -> f.stream == 'C', frames) == 1
    @test count(f -> f.stream == 'M', frames) == 1
    @test count(f -> f.stream == 'Q', frames) == 5
end

function test_inject_config_stored_under_prefix()
    frames = load_frames(GEOMETRY_PATH)
    config = _injection_config(nevent=3)
    inject!(frames, config)

    m_frame = TamboSim._get_last_frame(frames, 'M')
    @test haskey(m_frame.data, "injection")
    @test m_frame.data["injection"]["nevent"] == 3
end

function test_inject_q_frame_parents()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=3))

    g_frame = TamboSim._get_last_frame(frames, 'G')
    m_frame = TamboSim._get_last_frame(frames, 'M')
    q_frames = filter(f -> f.stream == 'Q', frames)

    for qf in q_frames
        @test qf.parents['G'] === g_frame
        @test qf.parents['M'] === m_frame
    end
end

function test_inject_custom_prefix()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=2); prefix="nu_injection")

    m_frame = TamboSim._get_last_frame(frames, 'M')
    @test haskey(m_frame.data, "nu_injection")

    q_frames = filter(f -> f.stream == 'Q', frames)
    for qf in q_frames
        @test haskey(qf, "event_id")
    end
end

function test_inject_missing_nevent_errors()
    frames = load_frames(GEOMETRY_PATH)
    bad_config = Dict{String,Any}("strategy" => "NeutrinoInjection", "pdg" => 16)
    @test_throws ErrorException inject!(frames, bad_config)
end

function test_inject_missing_strategy_errors()
    frames = load_frames(GEOMETRY_PATH)
    bad_config = _injection_config(nevent=2)
    delete!(bad_config, "strategy")
    @test_throws ErrorException inject!(frames, bad_config)
end

function test_inject_unknown_strategy_errors()
    frames = load_frames(GEOMETRY_PATH)
    bad_config = _injection_config(nevent=2)
    bad_config["strategy"] = "BogusInjection"
    @test_throws ErrorException inject!(frames, bad_config)
end

function test_inject_dispatches_to_protons()
    frames = load_frames(GEOMETRY_PATH)
    proton_config = Dict{String,Any}(
        "strategy"  => "CosmicRayInjection",
        "seed"  => 42,
        "nevent"    => 5,
        "pdg"       => 2212,
        "gamma"     => 2.7,
        "emin"      => 1e3,
        "emax"      => 1e7,
        "thetamin"  => 91.0,
        "thetamax"  => 130.0,
        "phimin"    => 0.0,
        "phimax"    => 360.0,
        "altitude"  => 50.0,
    )
    inject!(frames, proton_config)

    q_frames = filter(f -> f.stream == 'Q', frames)
    @test length(q_frames) == 5
    # Proton path stamps a `SurfaceCRPoint` at `phase_space_point`; the
    # neutrino path stamps a different point type. This confirms dispatch
    # routed to inject_protons!.
    @test any(f -> haskey(f, "phase_space_point") &&
                   f["phase_space_point"] isa SurfaceCRPoint, q_frames)
end

# =============================================================================
# neutrino initial_state position tests
# =============================================================================

function test_initial_state_at_earth_entry()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=30))

    q_frames = filter(f -> f.stream == 'Q', frames)
    # Only examine frames that completed injection (have both states)
    survived = filter(f -> haskey(f, "injection_initial_state") &&
                           haskey(f, "injection_taurunner_output_state"), q_frames)
    @test length(survived) > 0

    for q in survived
        istate  = q["injection_initial_state"]
        trstate = q["injection_taurunner_output_state"]

        # initial_state must not be NaN
        @test !any(isnan, ustrip.(istate.position.point))

        # The two positions must be distinct — initial is at Earth entry,
        # taurunner_output is wherever TauRunner's stopping condition fired
        # (somewhere along the path through the Earth, not necessarily near
        # the detector).
        disp = trstate.position.point .- istate.position.point
        dist = sqrt(sum(ustrip.(u"m", disp).^2))
        @test dist > 1.0   # at least 1 metre apart

        # The displacement from initial → taurunner_output must be parallel to
        # the neutrino direction (collinearity check via cross-product magnitude).
        d_hat = ustrip.(istate.direction.point)
        disp_hat = ustrip.(u"m", disp) ./ dist
        cross_mag = sqrt(sum((d_hat × disp_hat).^2))
        @test cross_mag < 1e-4
    end
end

# =============================================================================
# proposal_propagation! tests
# =============================================================================

function test_proposal_config_stored()
    is_proposal_available() || return

    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=5))
    filter!(f -> haskey(f, "injection_final_state"), frames)

    proposal_config = Dict{String,Any}(
        "seed"        => 7,
        "vcut"            => 0.5,
        "do_interpolate"  => true,
        "do_continuous"   => true,
        "tablespath"      => joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                                      "resources", "proposal_tables"),
    )
    proposal_propagation!(frames, proposal_config)

    m_frame = TamboSim._get_last_frame(frames, 'M')
    @test haskey(m_frame.data, "proposal")
    @test m_frame.data["proposal"]["vcut"] == 0.5
end

function test_proposal_output_keys()
    is_proposal_available() || return

    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=20))
    filter!(f -> haskey(f, "injection_final_state"), frames)
    count(f -> f.stream == 'Q', frames) > 0 || return

    proposal_config = Dict{String,Any}(
        "seed"        => 7,
        "vcut"            => 0.5,
        "do_interpolate"  => true,
        "do_continuous"   => true,
        "tablespath"      => joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                                      "resources", "proposal_tables"),
    )
    proposal_propagation!(frames, proposal_config)

    q_frames = filter(f -> f.stream == 'Q', frames)
    propagated = filter(f -> haskey(f, "proposal_final_state"), q_frames)
    @test length(propagated) > 0

    qf = first(propagated)
    @test haskey(qf, "proposal_final_state")
    @test haskey(qf, "proposal_decay_products")
    @test haskey(qf, "proposal_stochastic_losses")
    @test haskey(qf, "proposal_continuous_losses")
end

function test_proposal_skips_below_rest_energy()
    is_proposal_available() || return

    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=10))
    filter!(f -> haskey(f, "injection_final_state"), frames)
    q_frames = filter(f -> f.stream == 'Q', frames)
    isempty(q_frames) && return

    # Replace one Q frame's injection_final_state with a sub-rest-energy
    # electron (0.1 MeV total energy < 0.511 MeV rest energy). The guard
    # should skip it with a warning while leaving normal-energy frames
    # propagated as usual.
    target = first(q_frames)
    orig = target["injection_final_state"]
    target["injection_final_state"] = Particle(EMinus, 0.1u"MeV", orig.position, orig.direction)

    proposal_config = Dict{String,Any}(
        "seed"        => 7,
        "vcut"            => 0.5,
        "do_interpolate"  => true,
        "do_continuous"   => true,
        "tablespath"      => joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                                      "resources", "proposal_tables"),
    )

    @test_logs (:warn, r"rest energy") match_mode=:any proposal_propagation!(frames, proposal_config)

    # The mutated low-energy Q frame must not gain proposal output keys.
    @test !haskey(target, "proposal_final_state")
    @test !haskey(target, "proposal_decay_products")
    @test !haskey(target, "proposal_stochastic_losses")
    @test !haskey(target, "proposal_continuous_losses")

    # At least one of the unmodified Q frames should have propagated.
    others = [f for f in q_frames if f !== target]
    if !isempty(others)
        @test any(haskey(f, "proposal_final_state") for f in others)
    end
end

# =============================================================================
# save_frames / load_frames tests
# =============================================================================

function test_save_load_roundtrip()
    # Build M+Q in memory — no real geometry needed for this test
    g_frame = Frame('G', Dict{String,Any}("site" => "test"))
    m_frame = Frame('M', Dict{String,Any}("cfg" => 42), Dict{Char,Frame}('G' => g_frame))
    q_parents = Dict{Char,Frame}('G' => g_frame, 'M' => m_frame)
    frames = Frame[
        g_frame,
        m_frame,
        Frame('Q', Dict{String,Any}("event_id" => 1, "val" => 1.0), q_parents),
        Frame('Q', Dict{String,Any}("event_id" => 2, "val" => 2.0), q_parents),
    ]

    path = tempname() * ".jld2"
    save_frames(path, frames)  # default: M+Q only
    loaded = load_frames(path)
    rm(path)

    @test count(f -> f.stream == 'M', loaded) == 1
    @test count(f -> f.stream == 'Q', loaded) == 2
    @test count(f -> f.stream == 'G', loaded) == 0
end

function test_save_load_data_preserved()
    g_frame = Frame('G', Dict{String,Any}("site" => "test"))
    m_frame = Frame('M', Dict{String,Any}("run" => "abc"), Dict{Char,Frame}('G' => g_frame))
    q_parents = Dict{Char,Frame}('G' => g_frame, 'M' => m_frame)
    qf = Frame('Q', Dict{String,Any}("event_id" => 99, "energy" => 1.5e6), q_parents)
    frames = Frame[g_frame, m_frame, qf]

    path = tempname() * ".jld2"
    save_frames(path, frames)
    loaded = load_frames(path)
    rm(path)

    loaded_q = first(filter(f -> f.stream == 'Q', loaded))
    @test loaded_q["event_id"] == 99
    @test loaded_q["energy"] ≈ 1.5e6
    # M frame data accessible via parent inheritance
    @test loaded_q["run"] == "abc"
end

function test_save_load_multi_file()
    # Two separate event files sharing the same geometry
    g_frame = Frame('G', Dict{String,Any}("site" => "test"))
    m1 = Frame('M', Dict{String,Any}("run" => 1), Dict{Char,Frame}('G' => g_frame))
    m2 = Frame('M', Dict{String,Any}("run" => 2), Dict{Char,Frame}('G' => g_frame))
    q_p1 = Dict{Char,Frame}('G' => g_frame, 'M' => m1)
    q_p2 = Dict{Char,Frame}('G' => g_frame, 'M' => m2)

    frames1 = Frame[g_frame, m1, Frame('Q', Dict{String,Any}("event_id" => 1), q_p1)]
    frames2 = Frame[g_frame, m2, Frame('Q', Dict{String,Any}("event_id" => 2), q_p2)]

    p1 = tempname() * ".jld2"
    p2 = tempname() * ".jld2"
    save_frames(p1, frames1, streams=('G','M','Q'))
    save_frames(p2, frames2, streams=('G','M','Q'))

    combined = load_frames([p1, p2])
    rm(p1); rm(p2)

    q_frames = filter(f -> f.stream == 'Q', combined)
    @test length(q_frames) == 2

    q1 = first(filter(f -> f["event_id"] == 1, q_frames))
    q2 = first(filter(f -> f["event_id"] == 2, q_frames))
    @test q1.m_frame["run"] == 1
    @test q2.m_frame["run"] == 2
end

function test_save_geometry_self_contained()
    # G frame saved with streams=('G',) should reload without needing the source file
    frames = load_frames(GEOMETRY_PATH)
    g_frame = TamboSim._get_last_frame(frames, 'G')

    path = tempname() * ".jld2"
    save_frames(path, frames, streams=('G',))
    loaded = load_frames(path)
    rm(path)

    @test count(f -> f.stream == 'G', loaded) == 1
    lg = TamboSim._get_last_frame(loaded, 'G')
    @test length(lg["topography"]) == length(g_frame["topography"])
    @test lg["geometry_hash"] == g_frame["geometry_hash"]
end

# =============================================================================
# relativize! tests
# =============================================================================

function test_relativize_tambosim_path_placeholder()
    pkg_root = get_tambosim_path()
    d = Dict{String,Any}("path" => "_TAMBOSIM_PATH_/resources/foo.h5")
    relativize!(d)
    @test d["path"] == "$pkg_root/resources/foo.h5"
end

function test_relativize_relative_path()
    pkg_root = get_tambosim_path()
    d = Dict{String,Any}("path" => "resources/geometry/colca_valley.h5")
    relativize!(d)
    @test d["path"] == joinpath(pkg_root, "resources/geometry/colca_valley.h5")
end

function test_relativize_absolute_path_untouched()
    d = Dict{String,Any}("path" => "/absolute/path/to/file.h5")
    relativize!(d)
    @test d["path"] == "/absolute/path/to/file.h5"
end

function test_relativize_non_path_string_untouched()
    d = Dict{String,Any}("label" => "my_label", "count" => 42)
    relativize!(d)
    @test d["label"] == "my_label"
    @test d["count"] == 42
end

function test_relativize_nested_dict()
    pkg_root = get_tambosim_path()
    d = Dict{String,Any}(
        "injection" => Dict{String,Any}(
            "xs_location" => "_TAMBOSIM_PATH_/resources/xs.h5"
        )
    )
    relativize!(d)
    @test d["injection"]["xs_location"] == "$pkg_root/resources/xs.h5"
end

function test_relativize_non_string_value_untouched()
    d = Dict{String,Any}("gamma" => 2.7, "nevent" => 1000, "flag" => true)
    relativize!(d)
    @test d["gamma"] === 2.7
    @test d["nevent"] === 1000
    @test d["flag"] === true
end

function _with_env(pairs::Pair{String,String}...; f)
    saved = Dict{String,Union{String,Nothing}}()
    for (k, _) in pairs
        saved[k] = haskey(ENV, k) ? ENV[k] : nothing
    end
    try
        for (k, v) in pairs
            ENV[k] = v
        end
        f()
    finally
        for (k, v) in saved
            v === nothing ? delete!(ENV, k) : (ENV[k] = v)
        end
    end
end

function test_relativize_tambo_data_path_placeholder()
    _with_env("TAMBO_DATA_PATH" => "/host/data"; f = () -> begin
        d = Dict{String,Any}("out" => "_TAMBO_DATA_PATH_/run_001/triggered.jld2")
        relativize!(d)
        @test d["out"] == "/host/data/run_001/triggered.jld2"
    end)
end

function test_relativize_tambo_corsika_and_flupro_placeholders()
    _with_env(
        "TAMBO_CORSIKA_PATH" => "/usr/local/bin/tambo_shower",
        "TAMBO_FLUPRO_PATH"  => "/opt/fluka";
        f = () -> begin
            d = Dict{String,Any}(
                "corsika_path" => "_TAMBO_CORSIKA_PATH_",
                "FLUPRO"       => "_TAMBO_FLUPRO_PATH_",
            )
            relativize!(d)
            @test d["corsika_path"] == "/usr/local/bin/tambo_shower"
            @test d["FLUPRO"] == "/opt/fluka"
        end,
    )
end

function test_relativize_env_placeholder_unset_yields_empty()
    # When the env var is unset, the placeholder substitutes to "" — leaving
    # any surrounding path with the empty prefix. Documents the contract.
    saved = haskey(ENV, "TAMBO_DATA_PATH") ? ENV["TAMBO_DATA_PATH"] : nothing
    delete!(ENV, "TAMBO_DATA_PATH")
    try
        d = Dict{String,Any}("out" => "_TAMBO_DATA_PATH_/run_001/triggered.jld2")
        relativize!(d)
        @test d["out"] == "/run_001/triggered.jld2"
    finally
        saved === nothing || (ENV["TAMBO_DATA_PATH"] = saved)
    end
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Simulation API" begin
        run_simulation_api_tests()
    end
end
