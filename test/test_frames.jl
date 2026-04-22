"""
Tests for the Frame data structure.
"""

function run_frame_tests()
    @testset "Frame Construction" begin
        test_frame_construction()
        test_frame_with_data()
        test_frame_with_parents()
    end

    @testset "Frame Access" begin
        test_frame_getindex()
        test_frame_setindex()
        test_frame_haskey()
        test_frame_keys()
        test_frame_getkey_default()
    end

    @testset "Frame Hierarchy" begin
        test_frame_parent_lookup()
        test_frame_override_parent()
        test_frame_hierarchy_order()
    end

    @testset "Frame Utilities" begin
        test_cut_frames_q_only()
        test_cut_frames_preserves_gc()
    end
end

function test_frame_construction()
    f = Frame('Q')
    @test isempty(f.data)
    @test isempty(f.parents)
    @test f.stream == 'Q'
end

function test_frame_with_data()
    data = Dict{String,Any}("key1" => 1, "key2" => "value")
    f = Frame('Q', data)
    @test f.data == data
    @test f["key1"] == 1
    @test f["key2"] == "value"
end

function test_frame_with_parents()
    gframe = Frame('G', Dict{String,Any}("earth_path" => "/tmp/earth.h5"))
    cframe = Frame('C', Dict{String,Any}("nevent" => 100))
    cframe.parents['G'] = gframe

    @test cframe["earth_path"] == "/tmp/earth.h5"
    @test cframe["nevent"] == 100
    @test cframe.stream == 'C'
    @test length(cframe.parents) == 1
end

function test_frame_getindex()
    f = Frame('Q', Dict{String,Any}("key" => 42))
    @test f["key"] == 42
    @test_throws KeyError f["nonexistent"]
end

function test_frame_setindex()
    f = Frame('Q')
    f["new_key"] = "new_value"
    @test f["new_key"] == "new_value"
    @test haskey(f, "new_key")
end

function test_frame_haskey()
    gframe = Frame('G', Dict{String,Any}("parent_key" => 1))
    child = Frame('Q', Dict{String,Any}("child_key" => 2))
    child.parents['G'] = gframe

    @test haskey(child, "child_key")
    @test haskey(child, "parent_key")
    @test !haskey(child, "nonexistent")
end

function test_frame_keys()
    gframe = Frame('G', Dict{String,Any}("a" => 1, "b" => 2))
    child = Frame('Q', Dict{String,Any}("c" => 3, "d" => 4))
    child.parents['G'] = gframe

    all_keys = keys(child)
    @test "a" in all_keys
    @test "b" in all_keys
    @test "c" in all_keys
    @test "d" in all_keys
end

function test_frame_getkey_default()
    f = Frame('Q', Dict{String,Any}("exists" => 10))
    @test getkey(f, "exists", 0) == 10
    @test getkey(f, "nonexistent", 0) == 0
end

function test_frame_parent_lookup()
    gframe = Frame('G', Dict{String,Any}("gp_key" => 100))
    cframe = Frame('C', Dict{String,Any}("p_key" => 200))
    cframe.parents['G'] = gframe
    qframe = Frame('Q', Dict{String,Any}("c_key" => 300))
    qframe.parents['G'] = gframe
    qframe.parents['C'] = cframe

    @test qframe["gp_key"] == 100
    @test qframe["p_key"] == 200
    @test qframe["c_key"] == 300
end

function test_frame_override_parent()
    gframe = Frame('G', Dict{String,Any}("key" => "g_value"))
    qframe = Frame('Q', Dict{String,Any}("key" => "q_value"))
    qframe.parents['G'] = gframe

    # Own data takes priority over parent
    @test qframe["key"] == "q_value"
    @test gframe["key"] == "g_value"
end

function test_frame_hierarchy_order()
    # G takes precedence over C when both define the same key
    gframe = Frame('G', Dict{String,Any}("shared" => "from_g"))
    cframe = Frame('C', Dict{String,Any}("shared" => "from_c"))
    qframe = Frame('Q')
    qframe.parents['G'] = gframe
    qframe.parents['C'] = cframe

    @test qframe["shared"] == "from_g"
end

function test_cut_frames_q_only()
    frames = Frame[
        Frame('G', Dict{String,Any}("geo" => true)),
        Frame('C', Dict{String,Any}("cfg" => true)),
    ]
    for v in [10, 20, 30, 40, 50]
        push!(frames, Frame('Q', Dict{String,Any}("value" => v)))
    end

    cut_frames!(frames, f -> f["value"] > 25)

    q_frames = filter(f -> f.stream == 'Q', frames)
    @test length(q_frames) == 3
    @test all(f -> f["value"] > 25, q_frames)
end

function test_cut_frames_preserves_gc()
    frames = Frame[
        Frame('G', Dict{String,Any}("geo" => true)),
        Frame('C', Dict{String,Any}("cfg" => true)),
        Frame('Q', Dict{String,Any}("value" => 5)),   # will be cut
        Frame('Q', Dict{String,Any}("value" => 50)),  # kept
    ]

    cut_frames!(frames, f -> f["value"] > 25)

    @test length(frames) == 3
    @test frames[1].stream == 'G'
    @test frames[2].stream == 'C'
    @test frames[3].stream == 'Q'
    @test frames[3]["value"] == 50
end
