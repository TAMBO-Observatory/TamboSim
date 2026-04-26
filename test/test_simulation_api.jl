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
        "pinecone"    => 7,
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
    end

    @testset "proposal_propagation!" begin
        test_proposal_config_stored()
        test_proposal_output_keys()
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
    end
end

# =============================================================================
# inject! tests
# =============================================================================

function test_inject_creates_c_and_q_frames()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=5))

    @test count(f -> f.stream == 'C', frames) == 1
    @test count(f -> f.stream == 'Q', frames) == 5
end

function test_inject_config_stored_under_prefix()
    frames = load_frames(GEOMETRY_PATH)
    config = _injection_config(nevent=3)
    inject!(frames, config)

    cframe = get_frame(frames, 'C')
    @test haskey(cframe.data, "injection")
    @test cframe.data["injection"]["nevent"] == 3
end

function test_inject_q_frame_parents()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=3))

    gframe = get_frame(frames, 'G')
    cframe = get_frame(frames, 'C')
    q_frames = filter(f -> f.stream == 'Q', frames)

    for qf in q_frames
        @test qf.parents['G'] === gframe
        @test qf.parents['C'] === cframe
    end
end

function test_inject_custom_prefix()
    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=2); prefix="nu_injection")

    cframe = get_frame(frames, 'C')
    @test haskey(cframe.data, "nu_injection")

    q_frames = filter(f -> f.stream == 'Q', frames)
    for qf in q_frames
        @test haskey(qf, "event_id")
    end
end

function test_inject_missing_nevent_errors()
    frames = load_frames(GEOMETRY_PATH)
    bad_config = Dict{String,Any}("pdg" => 16)
    @test_throws ErrorException inject!(frames, bad_config)
end

# =============================================================================
# proposal_propagation! tests
# =============================================================================

function test_proposal_config_stored()
    is_proposal_available() || return

    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=5))
    cut_frames!(frames, f -> haskey(f, "injection_final_state"))

    proposal_config = Dict{String,Any}(
        "pinecone"        => 7,
        "ecut"            => -1,
        "vcut"            => 0.05,
        "do_interpolate"  => true,
        "do_continuous"   => true,
        "tablespath"      => joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                                      "resources", "proposal_tables"),
    )
    proposal_propagation!(frames, proposal_config)

    cframe = get_frame(frames, 'C')
    @test haskey(cframe.data, "proposal")
    @test cframe.data["proposal"]["vcut"] == 0.05
end

function test_proposal_output_keys()
    is_proposal_available() || return

    frames = load_frames(GEOMETRY_PATH)
    inject!(frames, _injection_config(nevent=20))
    cut_frames!(frames, f -> haskey(f, "injection_final_state"))
    count(f -> f.stream == 'Q', frames) > 0 || return

    proposal_config = Dict{String,Any}(
        "pinecone"        => 7,
        "ecut"            => -1,
        "vcut"            => 0.05,
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

# =============================================================================
# save_frames / load_frames tests
# =============================================================================

function test_save_load_roundtrip()
    # Build C+Q in memory — no real geometry needed for this test
    gframe = Frame('G', Dict{String,Any}("site" => "test"))
    cframe = Frame('C', Dict{String,Any}("cfg" => 42), Dict{Char,Frame}('G' => gframe))
    q_parents = Dict{Char,Frame}('G' => gframe, 'C' => cframe)
    frames = Frame[
        gframe,
        cframe,
        Frame('Q', Dict{String,Any}("event_id" => 1, "val" => 1.0), q_parents),
        Frame('Q', Dict{String,Any}("event_id" => 2, "val" => 2.0), q_parents),
    ]

    path = tempname() * ".jld2"
    save_frames(path, frames)  # default: C+Q only
    loaded = load_frames(path)
    rm(path)

    @test count(f -> f.stream == 'C', loaded) == 1
    @test count(f -> f.stream == 'Q', loaded) == 2
    @test count(f -> f.stream == 'G', loaded) == 0
end

function test_save_load_data_preserved()
    gframe = Frame('G', Dict{String,Any}("site" => "test"))
    cframe = Frame('C', Dict{String,Any}("run" => "abc"), Dict{Char,Frame}('G' => gframe))
    q_parents = Dict{Char,Frame}('G' => gframe, 'C' => cframe)
    qf = Frame('Q', Dict{String,Any}("event_id" => 99, "energy" => 1.5e6), q_parents)
    frames = Frame[gframe, cframe, qf]

    path = tempname() * ".jld2"
    save_frames(path, frames)
    loaded = load_frames(path)
    rm(path)

    loaded_q = first(filter(f -> f.stream == 'Q', loaded))
    @test loaded_q["event_id"] == 99
    @test loaded_q["energy"] ≈ 1.5e6
    # C frame data accessible via parent inheritance
    @test loaded_q["run"] == "abc"
end

function test_save_load_multi_file()
    # Two separate event files sharing the same geometry
    gframe = Frame('G', Dict{String,Any}("site" => "test"))
    c1 = Frame('C', Dict{String,Any}("run" => 1), Dict{Char,Frame}('G' => gframe))
    c2 = Frame('C', Dict{String,Any}("run" => 2), Dict{Char,Frame}('G' => gframe))
    q_p1 = Dict{Char,Frame}('G' => gframe, 'C' => c1)
    q_p2 = Dict{Char,Frame}('G' => gframe, 'C' => c2)

    frames1 = Frame[gframe, c1, Frame('Q', Dict{String,Any}("event_id" => 1), q_p1)]
    frames2 = Frame[gframe, c2, Frame('Q', Dict{String,Any}("event_id" => 2), q_p2)]

    p1 = tempname() * ".jld2"
    p2 = tempname() * ".jld2"
    save_frames(p1, frames1, streams=('G','C','Q'))
    save_frames(p2, frames2, streams=('G','C','Q'))

    combined = load_frames([p1, p2])
    rm(p1); rm(p2)

    q_frames = filter(f -> f.stream == 'Q', combined)
    @test length(q_frames) == 2

    q1 = first(filter(f -> f["event_id"] == 1, q_frames))
    q2 = first(filter(f -> f["event_id"] == 2, q_frames))
    @test q1.cframe["run"] == 1
    @test q2.cframe["run"] == 2
end

function test_save_geometry_self_contained()
    # G frame saved with streams=('G',) should reload without needing the source file
    frames = load_frames(GEOMETRY_PATH)
    gframe = get_frame(frames, 'G')

    path = tempname() * ".jld2"
    save_frames(path, frames, streams=('G',))
    loaded = load_frames(path)
    rm(path)

    @test count(f -> f.stream == 'G', loaded) == 1
    lg = get_frame(loaded, 'G')
    @test length(lg["topography"]) == length(gframe["topography"])
    @test lg["earth_path"] == gframe["earth_path"]
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
